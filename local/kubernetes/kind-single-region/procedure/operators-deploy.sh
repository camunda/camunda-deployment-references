#!/bin/bash
set -euo pipefail

# Deploy prerequisite operators and their instances for Camunda on Kind
# This script deploys Elasticsearch (ECK), PostgreSQL (CloudNativePG), and Keycloak operators
# using the shared operator-based configurations from generic/kubernetes/operator-based/
#
# Usage:
#   CLUSTER_FILTER="pg-keycloak,pg-identity,pg-webmodeler" SECONDARY_STORAGE=elasticsearch CAMUNDA_MODE=domain ./operators-deploy.sh
#   SECONDARY_STORAGE=postgres CAMUNDA_MODE=no-domain ./operators-deploy.sh
#
# Environment variables:
#   SECONDARY_STORAGE  - Required: "elasticsearch" or "postgres"
#   CAMUNDA_MODE       - "domain" (TLS) or "no-domain" (port-forward), default: no-domain

# Validate SECONDARY_STORAGE is set (must be first check)
if [[ -z "${SECONDARY_STORAGE:-}" ]]; then
    echo "ERROR: SECONDARY_STORAGE environment variable is required."
    echo "       Valid values: elasticsearch, postgres"
    exit 1
fi

if [[ "$SECONDARY_STORAGE" != "elasticsearch" && "$SECONDARY_STORAGE" != "postgres" ]]; then
    echo "ERROR: Invalid SECONDARY_STORAGE value: $SECONDARY_STORAGE"
    echo "       Valid values: elasticsearch, postgres"
    exit 1
fi

CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
CAMUNDA_MODE=${CAMUNDA_MODE:-no-domain}

# Domain used for the ingress host and the OIDC issuer in domain mode.
# Kept in sync with camunda-deploy-domain.sh and helm-values/values-domain.yml.
# Exported so the Keycloak deploy.sh envsubst (issuer/hostname) picks it up.
CAMUNDA_DOMAIN="${CAMUNDA_DOMAIN:-camunda.example.com}"
export CAMUNDA_DOMAIN

# Set CLUSTER_FILTER based on SECONDARY_STORAGE
# When using Elasticsearch, only deploy PG clusters for Keycloak, Identity, and WebModeler
# When using PostgreSQL (RDBMS mode), deploy all PG clusters including the Camunda database
if [[ "$SECONDARY_STORAGE" == "elasticsearch" ]]; then
    CLUSTER_FILTER="pg-keycloak,pg-identity,pg-webmodeler"
else
    CLUSTER_FILTER=""
fi

export CAMUNDA_NAMESPACE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_BASE="$SCRIPT_DIR/../../../../generic/kubernetes/operator-based"
KIND_CONFIGS_DIR="$SCRIPT_DIR/../configs"

echo "Deploying operators for Kind ($CAMUNDA_MODE mode, secondary storage: $SECONDARY_STORAGE)..."

# 1. Deploy Elasticsearch via ECK operator (only when using elasticsearch as secondary storage)
# Uses Kind-specific elasticsearch config (2 replicas, soft anti-affinity)
# instead of the generic one (3 replicas, hard anti-affinity)
if [[ "$SECONDARY_STORAGE" == "postgres" ]]; then
    echo ""
    echo "=== Skipping Elasticsearch (ECK) — SECONDARY_STORAGE=postgres ==="
else
    echo ""
    echo "=== Deploying Elasticsearch (ECK) ==="
    (cd "$OPERATOR_BASE/elasticsearch" && ELASTICSEARCH_CLUSTER_FILE="$KIND_CONFIGS_DIR/elasticsearch-cluster.yml" ./deploy.sh)
fi

# 2. Deploy PostgreSQL via CloudNativePG operator
echo ""
echo "=== Deploying PostgreSQL (CloudNativePG) ==="
(
    cd "$OPERATOR_BASE/postgresql"

    # When using RDBMS mode, also deploy the orchestration cluster (pg-camunda)
    if [[ "$SECONDARY_STORAGE" == "postgres" ]]; then
        CLUSTER_FILTER="${CLUSTER_FILTER:+$CLUSTER_FILTER,}pg-camunda"
    fi

    CLUSTER_FILTER="$CLUSTER_FILTER" NAMESPACE="$CAMUNDA_NAMESPACE" ./deploy.sh
)

# 3. Deploy Keycloak via Keycloak operator
echo ""
echo "=== Deploying Keycloak ==="
(
    cd "$OPERATOR_BASE/keycloak"

    if [[ "$CAMUNDA_MODE" == "domain" ]]; then
        KEYCLOAK_CONFIG_FILE="keycloak-instance-domain-contour.yml" ./deploy.sh
    else
        KEYCLOAK_CONFIG_FILE="keycloak-instance-no-domain.yml" ./deploy.sh
    fi
)

# 4. Domain mode: wait until Keycloak is actually reachable *through the Contour
#    ingress* before returning (and therefore before Camunda is deployed).
#
#    The Keycloak CR reaching condition=Ready only means the pod is up; it does
#    NOT guarantee that Contour has programmed the /auth route or that Envoy has
#    a healthy upstream endpoint yet. If Camunda is deployed during that window,
#    every component fails OIDC discovery against
#    https://<domain>/auth/realms/camunda-platform with
#    "503 Service Unavailable ... upstream connect error ... Connection refused"
#    and crash-loops (camunda/camunda-deployment-references#2686).
#
#    We probe the realm-independent 'master' OIDC discovery document on purpose:
#    the camunda-platform realm does not exist yet (Identity creates it at
#    runtime, after the chart is installed), so gating on it would deadlock.
#    Kind publishes Envoy on 127.0.0.1:443, so --resolve reaches the ingress
#    without depending on /etc/hosts (which CI does not configure at this stage).
if [[ "$CAMUNDA_MODE" == "domain" ]]; then
    echo ""
    echo "=== Waiting for Keycloak to be reachable through the ingress ==="

    probe_url="https://${CAMUNDA_DOMAIN}/auth/realms/master/.well-known/openid-configuration"
    max_attempts=60
    probe_start=$SECONDS
    echo "Probing: ${probe_url}"

    for attempt in $(seq 1 "$max_attempts"); do
        if curl -fs -k -o /dev/null \
            --resolve "${CAMUNDA_DOMAIN}:443:127.0.0.1" \
            --connect-timeout 5 --max-time 10 "$probe_url"; then
            echo "✓ Keycloak OIDC issuer reachable through the ingress"
            break
        fi

        if [[ "$attempt" -eq "$max_attempts" ]]; then
            echo "ERROR: Keycloak not reachable through the ingress after ${max_attempts} attempts ($((SECONDS - probe_start))s)." >&2
            echo "       URL: ${probe_url}" >&2
            echo "       Deploying Camunda now would crash-loop on OIDC discovery" >&2
            echo "       (camunda/camunda-deployment-references#2686); aborting." >&2
            exit 1
        fi

        echo "  attempt ${attempt}/${max_attempts}: not reachable yet (waiting 5s)"
        sleep 5
    done
fi

echo ""
echo "✓ All operators deployed successfully"

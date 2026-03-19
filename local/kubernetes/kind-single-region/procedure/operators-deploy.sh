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
    pushd "$OPERATOR_BASE/elasticsearch" > /dev/null
    ELASTICSEARCH_CLUSTER_FILE="$KIND_CONFIGS_DIR/elasticsearch-cluster.yml" ./deploy.sh
    popd > /dev/null
fi

# 2. Deploy PostgreSQL via CloudNativePG operator
echo ""
echo "=== Deploying PostgreSQL (CloudNativePG) ==="
pushd "$OPERATOR_BASE/postgresql" > /dev/null
CLUSTER_FILTER="$CLUSTER_FILTER" NAMESPACE="$CAMUNDA_NAMESPACE" ./deploy.sh
popd > /dev/null

# 3. Deploy Keycloak via Keycloak operator
echo ""
echo "=== Deploying Keycloak ==="
pushd "$OPERATOR_BASE/keycloak" > /dev/null

if [[ "$CAMUNDA_MODE" == "domain" ]]; then
    export CAMUNDA_DOMAIN="camunda.example.com"
    KEYCLOAK_CONFIG_FILE="keycloak-instance-domain-nginx.yml" ./deploy.sh
else
    KEYCLOAK_CONFIG_FILE="keycloak-instance-no-domain.yml" ./deploy.sh
fi

popd > /dev/null

echo ""
echo "✓ All operators deployed successfully"

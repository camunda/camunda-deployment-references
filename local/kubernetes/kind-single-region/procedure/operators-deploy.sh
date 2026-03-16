#!/bin/bash
set -euo pipefail

# Deploy prerequisite operators and their instances for Camunda on Kind
# This script deploys Elasticsearch (ECK), PostgreSQL (CloudNativePG), and Keycloak operators
# using the shared operator-based configurations from generic/kubernetes/operator-based/
#
# Usage:
#   CAMUNDA_MODE=domain ./operators-deploy.sh   # Domain mode (TLS, uses camunda.example.com)
#   CAMUNDA_MODE=no-domain ./operators-deploy.sh # No-domain mode (port-forward)

CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
CAMUNDA_MODE=${CAMUNDA_MODE:-no-domain}
SKIP_ELASTICSEARCH=${SKIP_ELASTICSEARCH:-false}

export CAMUNDA_NAMESPACE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_BASE="$SCRIPT_DIR/../../../../generic/kubernetes/operator-based"
KIND_CONFIGS_DIR="$SCRIPT_DIR/../configs"

echo "Deploying operators for Kind ($CAMUNDA_MODE mode)..."

# 1. Deploy Elasticsearch via ECK operator (unless skipped for PG-only mode)
# Uses Kind-specific elasticsearch config (2 replicas, soft anti-affinity)
# instead of the generic one (3 replicas, hard anti-affinity)
if [[ "$SKIP_ELASTICSEARCH" == "true" ]]; then
    echo ""
    echo "=== Skipping Elasticsearch (ECK) — SKIP_ELASTICSEARCH=true ==="
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
NAMESPACE="$CAMUNDA_NAMESPACE" ./deploy.sh
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

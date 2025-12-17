#!/bin/bash
# =============================================================================
# Orchestration Migration - Step 2: Deploy Target Elasticsearch
# =============================================================================
# Deploys either ECK-managed Elasticsearch or configures Managed Service.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
STATE_DIR="${SCRIPT_DIR}/.state"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Orchestration Migration - Step 2: Deploy Target Elasticsearch"
echo "============================================================================="
echo ""

# -----------------------------------------------------------------------------
# Load state
# -----------------------------------------------------------------------------
if [[ ! -f "${STATE_DIR}/elasticsearch.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${STATE_DIR}/elasticsearch.env"

export NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"

# -----------------------------------------------------------------------------
# Choose target type
# -----------------------------------------------------------------------------
echo -e "${BLUE}=== Select Target Elasticsearch ===${NC}"
echo ""
echo "Choose your target Elasticsearch:"
echo "  1) ECK Operator (Elastic Cloud on Kubernetes)"
echo "  2) Managed Service (AWS OpenSearch, Elastic Cloud, Azure, etc.)"
echo ""
read -r -p "Enter choice (1 or 2): " TARGET_CHOICE

case "${TARGET_CHOICE}" in
    1)
        TARGET_TYPE="eck"
        echo ""
        echo -e "${GREEN}Selected: ECK Operator${NC}"
        ;;
    2)
        TARGET_TYPE="managed"
        echo ""
        echo -e "${GREEN}Selected: Managed Service${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo "TARGET_TYPE=${TARGET_TYPE}" >> "${STATE_DIR}/elasticsearch.env"
echo ""

# -----------------------------------------------------------------------------
# Deploy based on target type
# -----------------------------------------------------------------------------
if [[ "${TARGET_TYPE}" == "eck" ]]; then
    # -------------------------------------------------------------------------
    # ECK Operator deployment
    # -------------------------------------------------------------------------
    echo -e "${BLUE}=== Deploying ECK Elasticsearch Cluster ===${NC}"
    echo ""

    # Check ECK operator is installed
    if ! kubectl get crd elasticsearches.elasticsearch.k8s.elastic.co &>/dev/null; then
        echo -e "${RED}Error: ECK operator not installed${NC}"
        echo "Install with: kubectl apply -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml"
        echo "              kubectl apply -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml"
        exit 1
    fi
    echo -e "${GREEN}✓ ECK operator is installed${NC}"

    # Set ECK environment variables
    export ECK_CLUSTER_NAME="${CAMUNDA_RELEASE_NAME:-camunda}-elasticsearch-eck"
    export ES_VERSION="${ES_VERSION:-8.12.0}"
    export ES_REPLICAS="${ES_REPLICAS:-3}"
    export ES_STORAGE_SIZE="${ES_STORAGE_SIZE:-32Gi}"
    export ES_STORAGE_CLASS="${ES_STORAGE_CLASS:-}"
    export ES_MEMORY_REQUEST="${ES_MEMORY_REQUEST:-2Gi}"
    export ES_MEMORY_LIMIT="${ES_MEMORY_LIMIT:-2Gi}"
    export ES_CPU_REQUEST="${ES_CPU_REQUEST:-1}"
    export ES_CPU_LIMIT="${ES_CPU_LIMIT:-2}"

    echo ""
    echo "ECK Cluster Configuration:"
    echo "  Name: ${ECK_CLUSTER_NAME}"
    echo "  Version: ${ES_VERSION}"
    echo "  Replicas: ${ES_REPLICAS}"
    echo "  Storage: ${ES_STORAGE_SIZE}"
    echo ""

    # Generate and apply ECK cluster
    envsubst < "${TEMPLATES_DIR}/eck-cluster.yml" > "${STATE_DIR}/eck-cluster.yml"
    kubectl apply -f "${STATE_DIR}/eck-cluster.yml"

    echo ""
    echo -e "${BLUE}=== Waiting for ECK Cluster to be Ready ===${NC}"
    echo ""

    # Wait for cluster to be ready
    for i in {1..60}; do
        HEALTH=$(kubectl get elasticsearch "${ECK_CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.health}' 2>/dev/null || echo "unknown")
        if [[ "${HEALTH}" == "green" ]] || [[ "${HEALTH}" == "yellow" ]]; then
            echo -e "${GREEN}✓ ECK cluster is ready (health: ${HEALTH})${NC}"
            break
        fi
        echo "Waiting for ECK cluster... (${i}/60, current: ${HEALTH})"
        sleep 10
    done

    # Get ECK password
    _ECK_PASSWORD=$(kubectl get secret "${ECK_CLUSTER_NAME}-es-elastic-user" -n "${NAMESPACE}" -o jsonpath='{.data.elastic}' | base64 -d)

    # Save ECK state
    cat >> "${STATE_DIR}/elasticsearch.env" <<EOF
ECK_CLUSTER_NAME=${ECK_CLUSTER_NAME}
ECK_SERVICE=${ECK_CLUSTER_NAME}-es-http
TARGET_ES_HOST=${ECK_CLUSTER_NAME}-es-http.${NAMESPACE}.svc.cluster.local
TARGET_ES_PORT=9200
TARGET_ES_USERNAME=elastic
TARGET_ES_SECRET_NAME=${ECK_CLUSTER_NAME}-es-elastic-user
TARGET_ES_SECRET_KEY=elastic
EOF

    # Generate Helm values
    envsubst < "${TEMPLATES_DIR}/helm-values-eck.yml" > "${STATE_DIR}/helm-values-target.yml"

else
    # -------------------------------------------------------------------------
    # Managed Service configuration
    # -------------------------------------------------------------------------
    echo -e "${BLUE}=== Configure Managed Elasticsearch Service ===${NC}"
    echo ""
    echo "Enter your managed Elasticsearch connection details:"
    echo ""

    read -r -p "Elasticsearch Host (e.g., my-cluster.es.amazonaws.com): " MANAGED_ES_HOST
    read -r -p "Elasticsearch Port [9200]: " MANAGED_ES_PORT
    MANAGED_ES_PORT="${MANAGED_ES_PORT:-9200}"
    read -r -p "Protocol (http/https) [https]: " MANAGED_ES_PROTOCOL
    MANAGED_ES_PROTOCOL="${MANAGED_ES_PROTOCOL:-https}"
    read -r -p "TLS Enabled (true/false) [true]: " MANAGED_ES_TLS_ENABLED
    MANAGED_ES_TLS_ENABLED="${MANAGED_ES_TLS_ENABLED:-true}"
    read -r -p "Username [elastic]: " MANAGED_ES_USERNAME
    MANAGED_ES_USERNAME="${MANAGED_ES_USERNAME:-elastic}"
    read -r -p "Secret Name containing password: " MANAGED_ES_SECRET_NAME
    read -r -p "Secret Key for password [password]: " MANAGED_ES_SECRET_KEY
    MANAGED_ES_SECRET_KEY="${MANAGED_ES_SECRET_KEY:-password}"

    # Export for templates
    export MANAGED_ES_HOST MANAGED_ES_PORT MANAGED_ES_PROTOCOL MANAGED_ES_TLS_ENABLED
    export MANAGED_ES_USERNAME MANAGED_ES_SECRET_NAME MANAGED_ES_SECRET_KEY

    # Save managed service state
    cat >> "${STATE_DIR}/elasticsearch.env" <<EOF
TARGET_TYPE=managed
MANAGED_ES_HOST=${MANAGED_ES_HOST}
MANAGED_ES_PORT=${MANAGED_ES_PORT}
MANAGED_ES_PROTOCOL=${MANAGED_ES_PROTOCOL}
MANAGED_ES_TLS_ENABLED=${MANAGED_ES_TLS_ENABLED}
TARGET_ES_HOST=${MANAGED_ES_HOST}
TARGET_ES_PORT=${MANAGED_ES_PORT}
TARGET_ES_USERNAME=${MANAGED_ES_USERNAME}
TARGET_ES_SECRET_NAME=${MANAGED_ES_SECRET_NAME}
TARGET_ES_SECRET_KEY=${MANAGED_ES_SECRET_KEY}
EOF

    # Generate Helm values
    envsubst < "${TEMPLATES_DIR}/helm-values-managed.yml" > "${STATE_DIR}/helm-values-target.yml"

    echo ""
    echo -e "${YELLOW}⚠ Note: For managed services, you need to:${NC}"
    echo "  1. Ensure the cluster is accessible from your Kubernetes cluster"
    echo "  2. Create the secret with credentials: kubectl create secret generic ${MANAGED_ES_SECRET_NAME} --from-literal=${MANAGED_ES_SECRET_KEY}=<password>"
    echo "  3. Configure snapshot repository manually if you want to restore data"
    echo ""
fi

echo ""
echo "============================================================================="
echo -e "${GREEN}  Target Elasticsearch Configured!${NC}"
echo "============================================================================="
echo ""
echo "Helm values saved to: ${STATE_DIR}/helm-values-target.yml"
echo ""
echo "Next step: ./3-freeze.sh"
echo ""

#!/bin/bash
# =============================================================================
# Identity Migration - Step 2: Deploy Target PostgreSQL
# =============================================================================
# This script deploys the target PostgreSQL (CNPG or Managed Service).
# Uses templates with envsubst for YAML manifest generation.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
STATE_DIR="${SCRIPT_DIR}/.state"
OPERATORS_DIR="${SCRIPT_DIR}/../../2-deploy-operators"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Identity Migration - Step 2: Deploy Target PostgreSQL"
echo "============================================================================="
echo ""

# Check for skip
if [[ -f "${STATE_DIR}/skip" ]]; then
    # shellcheck source=/dev/null
    source "${STATE_DIR}/skip"
    echo -e "${YELLOW}Migration skipped: ${SKIP_REASON}${NC}"
    exit 0
fi

# Load state
if [[ ! -f "${STATE_DIR}/identity.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${STATE_DIR}/identity.env"

# -----------------------------------------------------------------------------
# Set environment variables for templates
# -----------------------------------------------------------------------------
export NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
export RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
export CNPG_CLUSTER_NAME="${CNPG_IDENTITY_CLUSTER:-pg-identity}"

# CNPG configuration from source
export PG_DATABASE="${PG_DATABASE:-identity}"
export PG_USERNAME="${PG_USERNAME:-identity}"
export PG_REPLICAS="${PG_REPLICAS:-1}"
export PG_STORAGE_SIZE="${PG_STORAGE_SIZE:-8Gi}"
export PG_STORAGE_CLASS="${PG_STORAGE_CLASS:-}"
export PG_MEMORY_REQUEST="${PG_MEMORY_REQUEST:-256Mi}"
export PG_MEMORY_LIMIT="${PG_MEMORY_LIMIT:-1Gi}"
export PG_CPU_REQUEST="${PG_CPU_REQUEST:-250m}"
export PG_CPU_LIMIT="${PG_CPU_LIMIT:-1}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

# =============================================================================
# Choose Target Type
# =============================================================================
echo -e "${BLUE}=== Configure PostgreSQL Target ===${NC}"
echo ""
echo "Choose your PostgreSQL target:"
echo "  1) Deploy CloudNativePG Operator (recommended for Kubernetes-native)"
echo "  2) Connect to Managed Service (RDS, Azure PostgreSQL, etc.)"
echo ""

read -r -p "Select option (1 or 2): " TARGET_OPTION

export TARGET_DB_TYPE=""
export TARGET_PG_HOST=""
export TARGET_PG_PORT="5432"
export TARGET_PG_USERNAME=""
export TARGET_PG_DATABASE="${PG_DATABASE:-identity}"
export DB_SECRET_NAME=""

case "$TARGET_OPTION" in
    1)
        TARGET_DB_TYPE="cnpg"
        echo ""
        echo -e "${BLUE}=== Deploying CNPG Cluster ===${NC}"
        echo ""

        # Check/Install CNPG operator
        if ! kubectl get crd clusters.postgresql.cnpg.io &>/dev/null; then
            echo -e "${YELLOW}CNPG Operator not found. Installing...${NC}"
            "${OPERATORS_DIR}/deploy-cnpg.sh"
        else
            echo -e "${GREEN}✓ CNPG Operator is installed${NC}"
        fi
        echo ""

        echo "CNPG Cluster Configuration:"
        echo "  Name: ${CNPG_CLUSTER_NAME}"
        echo "  Replicas: ${PG_REPLICAS}"
        echo "  Storage: ${PG_STORAGE_SIZE}"
        echo ""

        # Generate password for PostgreSQL
        export PG_PASSWORD="${PG_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)}"
        export PG_SUPERUSER_PASSWORD="${PG_SUPERUSER_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)}"

        # Create secrets first (required before CNPG cluster)
        echo "Creating PostgreSQL secrets..."
        envsubst < "${TEMPLATES_DIR}/pg-secrets.yml" > "${STATE_DIR}/pg-secrets.yml"
        kubectl apply -f "${STATE_DIR}/pg-secrets.yml"
        echo -e "${GREEN}✓ PostgreSQL secrets created${NC}"
        echo ""

        # Generate and apply CNPG cluster
        echo "Deploying CNPG cluster..."
        envsubst < "${TEMPLATES_DIR}/cnpg-cluster.yml" > "${STATE_DIR}/cnpg-cluster.yml"
        kubectl apply -f "${STATE_DIR}/cnpg-cluster.yml"

        echo ""
        echo "Waiting for CNPG cluster to be ready..."
        for i in {1..60}; do
            STATUS=$(kubectl get cluster "${CNPG_CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
            echo "  Status: ${STATUS}"

            if [[ "$STATUS" == "Cluster in healthy state" ]]; then
                break
            fi

            if [[ $i -eq 60 ]]; then
                echo -e "${RED}Timeout waiting for CNPG cluster${NC}"
                exit 1
            fi

            sleep 10
        done

        echo -e "${GREEN}✓ CNPG cluster is ready!${NC}"

        export TARGET_PG_HOST="${CNPG_CLUSTER_NAME}-rw.${NAMESPACE}.svc.cluster.local"
        export TARGET_PG_USERNAME="${PG_USERNAME:-identity}"
        export DB_SECRET_NAME="${CNPG_CLUSTER_NAME}-secret"

        # Generate Helm values for CNPG
        envsubst < "${TEMPLATES_DIR}/helm-values-cnpg.yml" > "${STATE_DIR}/helm-values-target.yml"
        ;;

    2)
        TARGET_DB_TYPE="managed"
        echo ""
        echo -e "${BLUE}=== Configure Managed PostgreSQL Connection ===${NC}"
        echo ""

        read -r -p "PostgreSQL Host: " TARGET_PG_HOST
        read -r -p "PostgreSQL Port [5432]: " TARGET_PG_PORT
        TARGET_PG_PORT="${TARGET_PG_PORT:-5432}"
        read -r -p "PostgreSQL Database [identity]: " TARGET_PG_DATABASE
        TARGET_PG_DATABASE="${TARGET_PG_DATABASE:-identity}"
        read -r -p "PostgreSQL Username: " TARGET_PG_USERNAME
        read -r -sp "PostgreSQL Password: " TARGET_PG_PASSWORD
        echo ""

        export TARGET_PG_HOST TARGET_PG_PORT TARGET_PG_DATABASE TARGET_PG_USERNAME
        export DB_SECRET_NAME="${CNPG_CLUSTER_NAME}-secret"

        # Validate connection
        echo ""
        echo "Validating connection to managed PostgreSQL..."

        kubectl run pg-test-${RANDOM} \
            --image=postgres:15 \
            --restart=Never \
            --rm -i \
            --namespace="${NAMESPACE}" \
            --env="PGPASSWORD=${TARGET_PG_PASSWORD}" \
            -- psql -h "${TARGET_PG_HOST}" -p "${TARGET_PG_PORT}" -U "${TARGET_PG_USERNAME}" -d postgres -c "SELECT 1" &>/dev/null || {
            echo -e "${RED}Failed to connect to managed PostgreSQL${NC}"
            exit 1
        }

        echo -e "${GREEN}✓ Connection to managed PostgreSQL validated!${NC}"

        # Create secret for managed DB credentials
        kubectl create secret generic "${DB_SECRET_NAME}" \
            --namespace="${NAMESPACE}" \
            --from-literal=username="${TARGET_PG_USERNAME}" \
            --from-literal=password="${TARGET_PG_PASSWORD}" \
            --dry-run=client -o yaml | kubectl apply -f -

        # Generate Helm values for managed service
        envsubst < "${TEMPLATES_DIR}/helm-values-managed.yml" > "${STATE_DIR}/helm-values-target.yml"
        ;;

    *)
        echo -e "${RED}Invalid option. Please select 1 or 2.${NC}"
        exit 1
        ;;
esac

# Save target info
cat >> "${STATE_DIR}/identity.env" <<EOF

# Target Database Configuration
export TARGET_DB_TYPE="${TARGET_DB_TYPE}"
export TARGET_PG_HOST="${TARGET_PG_HOST}"
export TARGET_PG_PORT="${TARGET_PG_PORT}"
export TARGET_PG_USERNAME="${TARGET_PG_USERNAME}"
export TARGET_PG_DATABASE="${TARGET_PG_DATABASE}"
export CNPG_CLUSTER_NAME="${CNPG_CLUSTER_NAME}"
export DB_SECRET_NAME="${DB_SECRET_NAME}"
EOF

echo ""
echo "============================================================================="
echo -e "${GREEN}  Target PostgreSQL Ready!${NC}"
echo "============================================================================="
echo ""
echo "Target Type: ${TARGET_DB_TYPE^^}"
if [[ "$TARGET_DB_TYPE" == "cnpg" ]]; then
    echo "CNPG Cluster: ${CNPG_CLUSTER_NAME}"
fi
echo "Host: ${TARGET_PG_HOST}:${TARGET_PG_PORT}"
echo "Database: ${TARGET_PG_DATABASE}"
echo "Helm values: ${STATE_DIR}/helm-values-target.yml"
echo ""
echo "Next step: ./3-freeze.sh"
echo ""

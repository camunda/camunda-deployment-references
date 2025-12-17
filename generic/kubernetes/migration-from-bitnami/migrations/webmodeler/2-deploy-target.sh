#!/bin/bash
# =============================================================================
# WebModeler Migration - Step 2: Deploy Target PostgreSQL
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
echo "  WebModeler Migration - Step 2: Deploy Target PostgreSQL"
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
if [[ ! -f "${STATE_DIR}/webmodeler.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${STATE_DIR}/webmodeler.env"

# -----------------------------------------------------------------------------
# Set environment variables for templates
# -----------------------------------------------------------------------------
export NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
export RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
export CNPG_CLUSTER_NAME="${CNPG_WEBMODELER_CLUSTER:-pg-webmodeler}"

# CNPG configuration from source
export PG_DATABASE="${PG_DATABASE:-webmodeler}"
export PG_USERNAME="${PG_USERNAME:-webmodeler}"
export PG_REPLICAS="${PG_REPLICAS:-1}"
export PG_STORAGE_SIZE="${PG_STORAGE_SIZE:-15Gi}"
export PG_IMAGE="${PG_IMAGE:-ghcr.io/cloudnative-pg/postgresql:17.5}"

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

        # Generate passwords for PostgreSQL
        export PG_PASSWORD="${PG_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)}"
        export PG_SUPERUSER_PASSWORD="${PG_SUPERUSER_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)}"

        # Create secrets first (required before CNPG cluster)
        echo "Creating PostgreSQL secrets..."
        envsubst < "${TEMPLATES_DIR}/pg-secrets.yml" > "${STATE_DIR}/pg-secrets.yml"
        kubectl apply -f "${STATE_DIR}/pg-secrets.yml"
        echo -e "${GREEN}✓ PostgreSQL secrets created${NC}"
        echo ""

        # Deploy CNPG cluster
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

        export TARGET_PG_HOST="${CNPG_CLUSTER_NAME}-rw"

        # Generate Helm values for CNPG
        envsubst < "${TEMPLATES_DIR}/helm-values-cnpg.yml" > "${STATE_DIR}/helm-values-target.yml"
        echo -e "${GREEN}✓ Helm values generated${NC}"
        ;;

    2)
        TARGET_DB_TYPE="managed"
        echo ""
        echo -e "${BLUE}=== Configure Managed PostgreSQL Connection ===${NC}"
        echo ""

        read -r -p "PostgreSQL Host: " TARGET_PG_HOST
        read -r -p "PostgreSQL Port [5432]: " TARGET_PG_PORT
        TARGET_PG_PORT="${TARGET_PG_PORT:-5432}"
        read -r -p "PostgreSQL Database [webmodeler]: " PG_DATABASE
        PG_DATABASE="${PG_DATABASE:-webmodeler}"
        read -r -p "PostgreSQL Username: " PG_USERNAME
        read -r -sp "PostgreSQL Password: " PG_PASSWORD
        echo ""

        export TARGET_PG_HOST TARGET_PG_PORT PG_DATABASE PG_USERNAME PG_PASSWORD
        export PG_SUPERUSER_PASSWORD="${PG_PASSWORD}"

        # Validate connection
        echo ""
        echo "Validating connection to managed PostgreSQL..."

        kubectl run pg-test-${RANDOM} \
            --image=postgres:15 \
            --restart=Never \
            --rm -i \
            --namespace="${NAMESPACE}" \
            --env="PGPASSWORD=${PG_PASSWORD}" \
            -- psql -h "${TARGET_PG_HOST}" -p "${TARGET_PG_PORT}" -U "${PG_USERNAME}" -d postgres -c "SELECT 1" &>/dev/null || {
            echo -e "${YELLOW}⚠ Could not validate connection to managed PostgreSQL${NC}"
            echo "Please verify the connection details are correct."
            read -r -p "Continue anyway? (yes/no): " continue_anyway
            if [[ "$continue_anyway" != "yes" ]]; then
                exit 1
            fi
        }

        echo -e "${GREEN}✓ Connection validated${NC}"

        # Create secret for managed DB credentials
        envsubst < "${TEMPLATES_DIR}/pg-secrets.yml" > "${STATE_DIR}/pg-secrets.yml"
        kubectl apply -f "${STATE_DIR}/pg-secrets.yml"
        echo -e "${GREEN}✓ Database credentials secret created${NC}"

        # Generate Helm values for managed service
        envsubst < "${TEMPLATES_DIR}/helm-values-managed.yml" > "${STATE_DIR}/helm-values-target.yml"
        echo -e "${GREEN}✓ Helm values generated${NC}"
        ;;

    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

# =============================================================================
# Save Target Configuration
# =============================================================================
echo ""
echo -e "${BLUE}=== Saving Target Configuration ===${NC}"
echo ""

cat >> "${STATE_DIR}/webmodeler.env" <<EOF

# Target PostgreSQL configuration
export TARGET_DB_TYPE="${TARGET_DB_TYPE}"
export TARGET_PG_HOST="${TARGET_PG_HOST}"
export TARGET_PG_PORT="${TARGET_PG_PORT}"
export TARGET_PG_DATABASE="${PG_DATABASE}"
export CNPG_CLUSTER_NAME="${CNPG_CLUSTER_NAME}"
EOF

echo -e "${GREEN}✓ Target configuration saved${NC}"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Target PostgreSQL Deployed!${NC}"
echo "============================================================================="
echo ""
echo "Target: ${TARGET_DB_TYPE^^}"
if [[ "$TARGET_DB_TYPE" == "cnpg" ]]; then
    echo "  CNPG Cluster: ${CNPG_CLUSTER_NAME}"
    echo "  Service: ${TARGET_PG_HOST}"
else
    echo "  Managed Service: ${TARGET_PG_HOST}:${TARGET_PG_PORT}"
fi
echo "Database: ${PG_DATABASE}"
echo ""
echo "Generated files:"
echo "  - ${STATE_DIR}/helm-values-target.yml"
echo ""
echo "Next step: ./3-freeze.sh"
echo ""

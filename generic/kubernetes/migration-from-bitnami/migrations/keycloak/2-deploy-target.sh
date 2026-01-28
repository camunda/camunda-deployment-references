#!/bin/bash
# =============================================================================
# Keycloak Migration - Step 2: Deploy Target Infrastructure
# =============================================================================
# This script deploys the target Keycloak Operator instance and (if integrated
# PostgreSQL mode) either a CNPG cluster or connects to a managed service.
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
echo "  Keycloak Migration - Step 2: Deploy Target Infrastructure"
echo "============================================================================="
echo ""

# Check for skip
if [[ -f "${STATE_DIR}/skip" ]]; then
    # shellcheck source=/dev/null
    source "${STATE_DIR}/skip"
    echo -e "${YELLOW}Migration skipped: ${SKIP_REASON}${NC}"
    exit 0
fi

# Load state from introspection
if [[ ! -f "${STATE_DIR}/keycloak.env" ]]; then
    echo -e "${RED}Error: Introspection state not found. Run ./0-introspect.sh first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${STATE_DIR}/keycloak.env"

# -----------------------------------------------------------------------------
# Set environment variables for templates
# -----------------------------------------------------------------------------
export NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
export RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
export BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"
export CNPG_CLUSTER_NAME="${CNPG_KEYCLOAK_CLUSTER:-pg-keycloak}"

# CNPG configuration
export PG_DATABASE="${KEYCLOAK_DB_NAME:-keycloak}"
export PG_USERNAME="${PG_USERNAME:-keycloak}"
export PG_REPLICAS="${PG_REPLICAS:-1}"
export PG_STORAGE_SIZE="${PG_STORAGE_SIZE:-15Gi}"
export PG_IMAGE="${PG_IMAGE:-ghcr.io/cloudnative-pg/postgresql:17.5}"

# Keycloak configuration
export KEYCLOAK_CR_NAME="${KEYCLOAK_OPERATOR_INSTANCE:-keycloak}"
export KC_IMAGE="${KC_IMAGE:-docker.io/camunda/keycloak:quay-optimized-26.3.2}"
export KC_REPLICAS="${KC_REPLICAS:-1}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "PostgreSQL Mode: ${PG_MODE}"
echo ""

# =============================================================================
# Step 1: Check/Install Keycloak Operator
# =============================================================================
echo -e "${BLUE}=== Checking Keycloak Operator ===${NC}"
echo ""

if ! kubectl get crd keycloaks.k8s.keycloak.org &>/dev/null; then
    echo -e "${YELLOW}Keycloak Operator not found. Installing...${NC}"
    "${OPERATORS_DIR}/deploy-keycloak-operator.sh"
else
    echo -e "${GREEN}✓ Keycloak Operator is installed${NC}"
fi
echo ""

# =============================================================================
# Step 2: Deploy PostgreSQL Target (if integrated mode)
# =============================================================================
export TARGET_DB_TYPE="external"
export TARGET_PG_HOST=""
export TARGET_PG_PORT="5432"

if [[ "$PG_MODE" == "integrated" ]]; then
    echo -e "${BLUE}=== Configuring PostgreSQL Target ===${NC}"
    echo ""
    echo "Choose your PostgreSQL target:"
    echo "  1) Deploy CloudNativePG Operator (recommended for Kubernetes-native)"
    echo "  2) Connect to Managed Service (RDS, Azure PostgreSQL, etc.)"
    echo ""

    read -r -p "Select option (1 or 2): " PG_TARGET_OPTION

    case "$PG_TARGET_OPTION" in
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
            ;;

        2)
            TARGET_DB_TYPE="managed"
            echo ""
            echo -e "${BLUE}=== Configure Managed PostgreSQL Connection ===${NC}"
            echo ""

            read -r -p "PostgreSQL Host: " TARGET_PG_HOST
            read -r -p "PostgreSQL Port [5432]: " TARGET_PG_PORT
            TARGET_PG_PORT="${TARGET_PG_PORT:-5432}"
            read -r -p "PostgreSQL Database [keycloak]: " PG_DATABASE
            PG_DATABASE="${PG_DATABASE:-keycloak}"
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
                echo -e "${RED}Failed to connect to managed PostgreSQL${NC}"
                exit 1
            }

            echo -e "${GREEN}✓ Connection to managed PostgreSQL validated!${NC}"

            # Create secret for managed DB credentials (using same template)
            envsubst < "${TEMPLATES_DIR}/pg-secrets.yml" > "${STATE_DIR}/pg-secrets.yml"
            kubectl apply -f "${STATE_DIR}/pg-secrets.yml"
            ;;

        *)
            echo -e "${RED}Invalid option. Please select 1 or 2.${NC}"
            exit 1
            ;;
    esac
else
    # External PostgreSQL - extract connection info from current Keycloak
    echo -e "${BLUE}=== Using External PostgreSQL ===${NC}"
    echo ""
    echo "Keycloak uses external PostgreSQL. Extracting connection details..."

    # Try to get the current DB connection from Keycloak env/secrets
    KC_JSON=$(kubectl get statefulset "${KC_STS_NAME}" -n "${NAMESPACE}" -o json)

    TARGET_PG_HOST=$(echo "$KC_JSON" | jq -r '.spec.template.spec.containers[0].env[] | select(.name == "KC_DB_URL_HOST") | .value // empty' || echo "")

    if [[ -z "$TARGET_PG_HOST" ]]; then
        echo "Could not auto-detect external PostgreSQL host."
        read -r -p "PostgreSQL Host: " TARGET_PG_HOST
        read -r -p "PostgreSQL Port [5432]: " TARGET_PG_PORT
        TARGET_PG_PORT="${TARGET_PG_PORT:-5432}"
    fi

    export TARGET_PG_HOST TARGET_PG_PORT
    echo -e "${GREEN}✓ External PostgreSQL: ${TARGET_PG_HOST}:${TARGET_PG_PORT}${NC}"
fi

# =============================================================================
# Step 3: Choose Domain Mode
# =============================================================================
echo ""
echo -e "${BLUE}=== Configure Keycloak Access Mode ===${NC}"
echo ""
echo "Choose how Keycloak will be accessed:"
echo "  1) With Domain - HTTPS via NGINX Ingress (production)"
echo "  2) Without Domain - HTTP via port-forward (local/development)"
echo ""

read -r -p "Select option (1 or 2): " DOMAIN_OPTION

export KEYCLOAK_DOMAIN_MODE=""
export CAMUNDA_DOMAIN=""

case "$DOMAIN_OPTION" in
    1)
        KEYCLOAK_DOMAIN_MODE="domain"
        echo ""
        read -r -p "Enter your domain (e.g., camunda.example.com): " CAMUNDA_DOMAIN
        export CAMUNDA_DOMAIN

        echo ""
        echo "Keycloak will be accessible at: https://${CAMUNDA_DOMAIN}/auth"
        echo ""

        # Generate Keycloak CR with domain
        echo "Generating Keycloak Operator CR (domain mode)..."
        envsubst < "${TEMPLATES_DIR}/keycloak-cr-domain.yml" > "${STATE_DIR}/keycloak-operator.yml"

        # Generate Helm values with domain
        envsubst < "${TEMPLATES_DIR}/helm-values-keycloak-domain.yml" > "${STATE_DIR}/helm-values-keycloak.yml"
        ;;

    2)
        KEYCLOAK_DOMAIN_MODE="no-domain"
        echo ""
        echo "Keycloak will be accessible via port-forward:"
        echo "  kubectl port-forward svc/${KEYCLOAK_CR_NAME}-service 18080:8080 -n ${NAMESPACE}"
        echo "  Then access: http://localhost:18080/auth"
        echo ""

        # Generate Keycloak CR without domain
        echo "Generating Keycloak Operator CR (no-domain mode)..."
        envsubst < "${TEMPLATES_DIR}/keycloak-cr-no-domain.yml" > "${STATE_DIR}/keycloak-operator.yml"

        # Generate Helm values without domain
        envsubst < "${TEMPLATES_DIR}/helm-values-keycloak-no-domain.yml" > "${STATE_DIR}/helm-values-keycloak.yml"
        ;;

    *)
        echo -e "${RED}Invalid option. Please select 1 or 2.${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}✓ Keycloak configuration generated${NC}"

# =============================================================================
# Step 4: Custom Volumes Warning
# =============================================================================
if [[ "${KC_HAS_CUSTOM_VOLUMES:-false}" == "true" ]]; then
    echo ""
    echo -e "${YELLOW}=============================================================================${NC}"
    echo -e "${YELLOW}  WARNING: Custom Volumes Detected${NC}"
    echo -e "${YELLOW}=============================================================================${NC}"
    echo ""
    echo "The following custom volumes were detected in your Keycloak installation:"
    echo "  Volumes: ${KC_CUSTOM_VOLUMES:-}"
    echo "  Mounts: ${KC_CUSTOM_MOUNTS:-}"
    echo ""
    echo "These may contain Themes or SPI providers that need manual configuration"
    echo "in the Keycloak CRD. Edit: ${STATE_DIR}/keycloak-operator.yml"
    echo ""
fi

# =============================================================================
# Save Target Configuration
# =============================================================================
cat >> "${STATE_DIR}/keycloak.env" <<EOF

# Target Database Configuration
export TARGET_DB_TYPE="${TARGET_DB_TYPE}"
export TARGET_PG_HOST="${TARGET_PG_HOST}"
export TARGET_PG_PORT="${TARGET_PG_PORT}"
export CNPG_CLUSTER_NAME="${CNPG_CLUSTER_NAME}"

# Keycloak Configuration
export KEYCLOAK_CR_NAME="${KEYCLOAK_CR_NAME}"
export KEYCLOAK_DOMAIN_MODE="${KEYCLOAK_DOMAIN_MODE}"
export CAMUNDA_DOMAIN="${CAMUNDA_DOMAIN}"
EOF

echo ""
echo "============================================================================="
echo -e "${GREEN}  Target Infrastructure Ready!${NC}"
echo "============================================================================="
echo ""
echo "PostgreSQL Target: ${TARGET_DB_TYPE^^}"
if [[ "$TARGET_DB_TYPE" == "cnpg" ]]; then
    echo "  CNPG Cluster: ${CNPG_CLUSTER_NAME}"
    echo "  Service: ${TARGET_PG_HOST}"
elif [[ "$TARGET_DB_TYPE" == "managed" ]]; then
    echo "  Managed Service: ${TARGET_PG_HOST}:${TARGET_PG_PORT}"
else
    echo "  External: ${TARGET_PG_HOST}:${TARGET_PG_PORT}"
fi
echo ""
echo "Keycloak Mode: ${KEYCLOAK_DOMAIN_MODE}"
if [[ "$KEYCLOAK_DOMAIN_MODE" == "domain" ]]; then
    echo "  URL: https://${CAMUNDA_DOMAIN}/auth"
else
    echo "  URL: http://localhost:18080/auth (via port-forward)"
fi
echo ""
echo "Generated files:"
echo "  - ${STATE_DIR}/keycloak-operator.yml"
echo "  - ${STATE_DIR}/helm-values-keycloak.yml"
echo ""
echo -e "${YELLOW}Note: Keycloak Operator instance will be deployed after data restore in step 4.${NC}"
echo ""
echo "Next step: ./3-freeze.sh"
echo ""

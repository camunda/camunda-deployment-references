#!/bin/bash
# =============================================================================
# Keycloak Migration - Step 5: Cutover Helm Release
# =============================================================================
# This script updates the Camunda Helm release to use the new Keycloak Operator
# instance and (if applicable) the new PostgreSQL backend.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION_STATE_DIR="${SCRIPT_DIR}/.state"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Keycloak Migration - Step 5: Cutover Helm Release"
echo "============================================================================="
echo ""

# Check for skip
if [[ -f "${MIGRATION_STATE_DIR}/skip" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/skip"
    echo -e "${YELLOW}Migration skipped: ${SKIP_REASON}${NC}"
    exit 0
fi

# Load state
if [[ ! -f "${MIGRATION_STATE_DIR}/keycloak.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${MIGRATION_STATE_DIR}/keycloak.env"

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "Chart Version: ${CHART_VERSION:-current}"
echo ""

# =============================================================================
# Step 1: Backup Current Helm Values
# =============================================================================
echo -e "${BLUE}=== Backing Up Current Helm Values ===${NC}"
echo ""

helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" > "${MIGRATION_STATE_DIR}/helm-values-backup.yaml"
echo -e "${GREEN}✓ Current values saved to: ${MIGRATION_STATE_DIR}/helm-values-backup.yaml${NC}"
echo ""

# =============================================================================
# Step 2: Generate Migration Values
# =============================================================================
echo -e "${BLUE}=== Generating Migration Values ===${NC}"
echo ""

# Build the migration values file
cat > "${MIGRATION_STATE_DIR}/helm-values-migration.yaml" <<EOF
# Migration values - Keycloak Operator
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Disable Bitnami Keycloak
keycloak:
  enabled: false

# Configure Identity to use Keycloak Operator
identity:
  keycloak:
    # Point to the Keycloak Operator service
    url:
      protocol: http
      host: ${KEYCLOAK_INSTANCE_NAME}-service.${NAMESPACE}.svc.cluster.local
      port: 80
    # Context path for Keycloak Operator
    contextPath: /auth
EOF

# Add PostgreSQL configuration if integrated mode
if [[ "$PG_MODE" == "integrated" ]]; then
    if [[ "${TARGET_DB_TYPE}" == "cnpg" ]]; then
        cat >> "${MIGRATION_STATE_DIR}/helm-values-migration.yaml" <<EOF

# Disable Bitnami PostgreSQL for Keycloak (now using CNPG)
# Note: The Keycloak Operator instance already points to CNPG
EOF
    elif [[ "${TARGET_DB_TYPE}" == "managed" ]]; then
        cat >> "${MIGRATION_STATE_DIR}/helm-values-migration.yaml" <<EOF

# Keycloak now uses managed PostgreSQL service
# Note: The Keycloak Operator instance already points to managed service
EOF
    fi
fi

echo "Migration values:"
cat "${MIGRATION_STATE_DIR}/helm-values-migration.yaml"
echo ""

# =============================================================================
# Step 3: Update Helm Release
# =============================================================================
echo -e "${BLUE}=== Updating Helm Release ===${NC}"
echo ""

echo -e "${YELLOW}This will update the Camunda Helm release to use Keycloak Operator.${NC}"
echo ""
read -r -p "Continue with Helm upgrade? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Cutover cancelled."
    exit 0
fi
echo ""

# Build helm upgrade command
HELM_CMD="helm upgrade ${RELEASE_NAME} camunda/camunda-platform"
HELM_CMD="${HELM_CMD} --namespace ${NAMESPACE}"
HELM_CMD="${HELM_CMD} --reuse-values"
HELM_CMD="${HELM_CMD} --values ${MIGRATION_STATE_DIR}/helm-values-migration.yaml"

if [[ -n "${CHART_VERSION}" ]]; then
    HELM_CMD="${HELM_CMD} --version ${CHART_VERSION}"
fi

HELM_CMD="${HELM_CMD} --wait --timeout 10m"

echo "Running: ${HELM_CMD}"
echo ""

eval "${HELM_CMD}"

echo ""
echo -e "${GREEN}✓ Helm release updated!${NC}"

# =============================================================================
# Step 4: Verify Identity is Running
# =============================================================================
echo ""
echo -e "${BLUE}=== Verifying Identity Component ===${NC}"
echo ""

IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"

if kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
    echo "Waiting for Identity to be ready..."
    kubectl rollout status deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || {
        echo -e "${YELLOW}Identity rollout taking longer than expected${NC}"
    }

    READY=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    echo "Identity: ${READY}/${DESIRED} ready"
else
    echo "Identity deployment not found (may not be enabled)"
fi

echo ""
echo "============================================================================="
echo -e "${GREEN}  Cutover Complete!${NC}"
echo "============================================================================="
echo ""
echo "Camunda is now using Keycloak Operator!"
echo ""
echo "Keycloak Service: ${KEYCLOAK_INSTANCE_NAME}-service.${NAMESPACE}.svc.cluster.local"
if [[ "$PG_MODE" == "integrated" ]]; then
    if [[ "${TARGET_DB_TYPE}" == "cnpg" ]]; then
        echo "PostgreSQL: CNPG cluster (${CNPG_CLUSTER_NAME})"
    elif [[ "${TARGET_DB_TYPE}" == "managed" ]]; then
        echo "PostgreSQL: Managed service (${TARGET_PG_HOST})"
    fi
fi
echo ""
echo "Next step: ./6-validate.sh"
echo ""

#!/bin/bash
# =============================================================================
# Identity Migration - Step 5: Cutover Helm Release
# =============================================================================
# This script updates the Camunda Helm release to use the new PostgreSQL.
# Uses pre-generated helm values from deploy-target step.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.state"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Identity Migration - Step 5: Cutover Helm Release"
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

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "Target Type: ${TARGET_DB_TYPE:-unknown}"
echo ""

# =============================================================================
# Backup Current Helm Values
# =============================================================================
echo -e "${BLUE}=== Backing Up Current Helm Values ===${NC}"
echo ""

helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" > "${STATE_DIR}/helm-values-backup.yaml"
echo -e "${GREEN}✓ Current values saved${NC}"
echo ""

# =============================================================================
# Display Generated Values
# =============================================================================
echo -e "${BLUE}=== Generated Helm Values for Target ===${NC}"
echo ""

if [[ ! -f "${STATE_DIR}/helm-values-target.yml" ]]; then
    echo -e "${RED}Error: Helm values not found. Run ./2-deploy-target.sh first${NC}"
    exit 1
fi

cat "${STATE_DIR}/helm-values-target.yml"
echo ""

# =============================================================================
# Confirm and Upgrade
# =============================================================================
echo ""
echo -e "${YELLOW}This will upgrade the Helm release with the above values.${NC}"
echo ""
read -r -p "Continue with Helm upgrade? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Cutover cancelled."
    echo "Values file is available at: ${STATE_DIR}/helm-values-target.yml"
    echo "You can manually run:"
    echo "  helm upgrade ${RELEASE_NAME} camunda/camunda-platform -n ${NAMESPACE} --reuse-values -f ${STATE_DIR}/helm-values-target.yml"
    exit 0
fi
echo ""

echo -e "${BLUE}=== Upgrading Helm Release ===${NC}"
echo ""

HELM_CMD="helm upgrade ${RELEASE_NAME} camunda/camunda-platform"
HELM_CMD="${HELM_CMD} --namespace ${NAMESPACE}"
HELM_CMD="${HELM_CMD} --reuse-values"
HELM_CMD="${HELM_CMD} --values ${STATE_DIR}/helm-values-target.yml"

if [[ -n "${CHART_VERSION}" ]]; then
    HELM_CMD="${HELM_CMD} --version ${CHART_VERSION}"
fi

HELM_CMD="${HELM_CMD} --wait --timeout 10m"

echo "Running: ${HELM_CMD}"
echo ""

eval "${HELM_CMD}"

echo ""
echo -e "${GREEN}✓ Helm release upgraded!${NC}"

# =============================================================================
# Verify Identity is Running
# =============================================================================
echo ""
echo -e "${BLUE}=== Verifying Identity Component ===${NC}"
echo ""

IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"

echo "Waiting for Identity to be ready..."
kubectl rollout status deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || {
    echo -e "${YELLOW}Identity rollout taking longer than expected${NC}"
}

READY=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

echo "Identity: ${READY}/${DESIRED} ready"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Cutover Complete!${NC}"
echo "============================================================================="
echo ""
echo "Identity is now using ${TARGET_DB_TYPE^^} PostgreSQL!"
echo "Host: ${TARGET_PG_HOST}:${TARGET_PG_PORT}"
echo ""
echo "Next step: ./6-validate.sh"
echo ""

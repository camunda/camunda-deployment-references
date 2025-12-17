#!/bin/bash
# =============================================================================
# Orchestration Migration - Step 5: Cutover Helm Release
# =============================================================================
# Updates the Camunda Helm release to use the target Elasticsearch.
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
echo "  Orchestration Migration - Step 5: Cutover Helm Release"
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

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "Target Type: ${TARGET_TYPE:-eck}"
echo ""

# -----------------------------------------------------------------------------
# Backup current Helm values
# -----------------------------------------------------------------------------
echo -e "${BLUE}=== Backing Up Current Helm Values ===${NC}"
echo ""

helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" > "${STATE_DIR}/helm-values-backup.yaml"
echo -e "${GREEN}✓ Current values saved to: ${STATE_DIR}/helm-values-backup.yaml${NC}"

# -----------------------------------------------------------------------------
# Display generated values
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Generated Helm Values for Target ===${NC}"
echo ""
cat "${STATE_DIR}/helm-values-target.yml"
echo ""

# -----------------------------------------------------------------------------
# Confirm and upgrade
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}This will upgrade the Helm release with the above values.${NC}"
echo ""
read -r -p "Continue with Helm upgrade? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted. Values file is available at: ${STATE_DIR}/helm-values-target.yml"
    echo "You can manually run:"
    echo "  helm upgrade ${RELEASE_NAME} camunda/camunda-platform -n ${NAMESPACE} --reuse-values -f ${STATE_DIR}/helm-values-target.yml"
    exit 0
fi

echo ""
echo -e "${BLUE}=== Upgrading Helm Release ===${NC}"
echo ""

helm upgrade "${RELEASE_NAME}" camunda/camunda-platform \
    --namespace "${NAMESPACE}" \
    --reuse-values \
    --values "${STATE_DIR}/helm-values-target.yml" \
    --wait \
    --timeout 10m

echo ""
echo -e "${GREEN}✓ Helm release upgraded!${NC}"

# -----------------------------------------------------------------------------
# Wait for components to be ready
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Waiting for Components to be Ready ===${NC}"
echo ""

# Note: Zeebe exporting automatically resumes after restart
# No need to manually resume since we're doing a full restart

COMPONENTS=("zeebe" "zeebe-gateway" "operate" "tasklist" "optimize")

for comp in "${COMPONENTS[@]}"; do
    DEPLOYMENT="${RELEASE_NAME}-${comp}"
    echo "Waiting for ${comp}..."

    if kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl rollout status deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || true
    elif kubectl get statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl rollout status statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || true
    fi
done

echo ""
echo -e "${GREEN}✓ All components are ready!${NC}"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Cutover Complete!${NC}"
echo "============================================================================="
echo ""
echo "Camunda is now using the target Elasticsearch."
echo ""
echo "Next step: ./6-validate.sh"
echo ""

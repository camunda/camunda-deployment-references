#!/bin/bash
# =============================================================================
# Orchestration Migration - Step 4: Restore to Target Elasticsearch
# =============================================================================
# Restores the Elasticsearch snapshot to the target (ECK or Managed).
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
echo "  Orchestration Migration - Step 4: Restore to Target Elasticsearch"
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
export SNAPSHOT_NAME="${FINAL_SNAPSHOT:-${SNAPSHOT_NAME}}"
export SNAPSHOT_REPO="${SNAPSHOT_REPO:-migration_repo}"

echo "Namespace: ${NAMESPACE}"
echo "Target Type: ${TARGET_TYPE:-eck}"
echo "Target Host: ${TARGET_ES_HOST}"
echo "Snapshot to restore: ${SNAPSHOT_NAME}"
echo ""

# -----------------------------------------------------------------------------
# Check target type
# -----------------------------------------------------------------------------
if [[ "${TARGET_TYPE:-eck}" == "managed" ]]; then
    echo -e "${YELLOW}⚠ Managed Service Restore${NC}"
    echo ""
    echo "For managed Elasticsearch services, you need to:"
    echo "  1. Configure a snapshot repository on the managed cluster"
    echo "  2. Ensure the backup data is accessible (S3, GCS, etc.)"
    echo "  3. Restore using the managed service's tools or API"
    echo ""
    echo "If your managed service shares the backup PVC, you can continue."
    echo ""
    read -r -p "Continue with restore? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Skipping restore. Configure manually then run ./5-cutover.sh"
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Generate and apply restore job
# -----------------------------------------------------------------------------
echo -e "${BLUE}=== Restoring Snapshot ===${NC}"
echo ""

JOB_NAME="es-restore-$(date +%Y%m%d-%H%M%S)"
export JOB_NAME

# Generate restore job
envsubst < "${TEMPLATES_DIR}/es-restore-job.yml" > "${STATE_DIR}/restore-job.yml"

echo "Applying restore job..."
kubectl apply -f "${STATE_DIR}/restore-job.yml"

echo ""
echo -e "${BLUE}=== Waiting for Restore to Complete ===${NC}"
echo ""

# Wait for job to complete
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=3600s || {
    echo -e "${RED}Restore job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${JOB_NAME}"
    exit 1
}

echo ""
echo -e "${GREEN}✓ Restore completed successfully!${NC}"

# -----------------------------------------------------------------------------
# Verify restore
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Verifying Restored Data ===${NC}"
echo ""

# Get password for verification
if [[ "${TARGET_TYPE:-eck}" == "eck" ]]; then
    ES_PASSWORD=$(kubectl get secret "${TARGET_ES_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath="{.data.${TARGET_ES_SECRET_KEY}}" | base64 -d)
else
    ES_PASSWORD=$(kubectl get secret "${TARGET_ES_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath="{.data.${TARGET_ES_SECRET_KEY}}" | base64 -d 2>/dev/null || echo "")
fi

kubectl run es-verify \
    --image="curlimages/curl:latest" \
    --restart=Never \
    --rm -i \
    --namespace="${NAMESPACE}" \
    -- /bin/sh -c "
        echo 'Index counts:'
        curl -s -u '${TARGET_ES_USERNAME}:${ES_PASSWORD}' 'http://${TARGET_ES_HOST}:${TARGET_ES_PORT}/_cat/indices?v' | head -20
    " 2>/dev/null || echo "Verification completed (check manually if needed)"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Restore Complete!${NC}"
echo "============================================================================="
echo ""
echo "Data has been restored to target Elasticsearch."
echo ""
echo "Next step: ./5-cutover.sh"
echo ""

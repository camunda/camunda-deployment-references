#!/bin/bash
# =============================================================================
# Orchestration Migration - Step 3: Freeze Camunda Components
# =============================================================================
# Scales down Camunda components that use Elasticsearch to stop writes.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.state"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Orchestration Migration - Step 3: Freeze Camunda Components"
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
export RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

echo -e "${YELLOW}⚠ WARNING: This will cause downtime for Camunda applications!${NC}"
echo ""
read -r -p "Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 1: Soft pause Zeebe exporting (as per Camunda docs)
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Soft Pause Zeebe Exporting ===${NC}"
echo ""

ZEEBE_GATEWAY_SVC="${RELEASE_NAME}-zeebe-gateway"
ZEEBE_MGMT_PORT="9600"

echo "Soft pausing Zeebe exporting..."
kubectl run zeebe-soft-pause \
    --image="curlimages/curl:latest" \
    --restart=Never \
    --rm -i \
    --namespace="${NAMESPACE}" \
    -- curl -s -X POST "http://${ZEEBE_GATEWAY_SVC}:${ZEEBE_MGMT_PORT}/actuator/exporting/pause?soft=true" 2>/dev/null || {
        echo -e "${YELLOW}⚠ Could not soft pause Zeebe exporting (may be older version or gateway not ready)${NC}"
    }

# -----------------------------------------------------------------------------
# Step 2: Save current replica counts
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Saving Current Replica Counts ===${NC}"
echo ""

# Components that use Elasticsearch
COMPONENTS=("zeebe" "zeebe-gateway" "operate" "tasklist" "optimize")

# Save replica counts for rollback
true > "${STATE_DIR}/replica-counts.env"
for comp in "${COMPONENTS[@]}"; do
    DEPLOYMENT="${RELEASE_NAME}-${comp}"

    # Try deployment first, then statefulset
    REPLICAS=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || \
               kubectl get statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || \
               echo "0")

    echo "${comp}=${REPLICAS}" >> "${STATE_DIR}/replica-counts.env"
    echo "  ${comp}: ${REPLICAS} replicas"
done

# -----------------------------------------------------------------------------
# Step 3: Scale down components
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Scaling Down Components ===${NC}"
echo ""

for comp in "${COMPONENTS[@]}"; do
    DEPLOYMENT="${RELEASE_NAME}-${comp}"

    if kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl scale deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --replicas=0
        echo -e "${GREEN}✓ Scaled down deployment ${DEPLOYMENT}${NC}"
    elif kubectl get statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl scale statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" --replicas=0
        echo -e "${GREEN}✓ Scaled down statefulset ${DEPLOYMENT}${NC}"
    else
        echo -e "${YELLOW}⚠ Component ${DEPLOYMENT} not found, skipping${NC}"
    fi
done

# -----------------------------------------------------------------------------
# Step 4: Wait for pods to terminate
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Waiting for Pods to Terminate ===${NC}"
echo ""

for comp in "${COMPONENTS[@]}"; do
    echo "Waiting for ${comp} pods to terminate..."
    kubectl wait --for=delete pod -l "app.kubernetes.io/component=${comp}" -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true
done

echo ""
echo -e "${GREEN}✓ All components scaled down${NC}"

# -----------------------------------------------------------------------------
# Step 5: Create final backup snapshot
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Creating Final Backup ===${NC}"
echo ""

FINAL_SNAPSHOT="migration-final-$(date +%Y%m%d-%H%M%S)"
export FINAL_SNAPSHOT
export JOB_NAME="es-final-backup-${FINAL_SNAPSHOT}"
export ES_HOST="${ES_STS_NAME/-master/}.${NAMESPACE}.svc.cluster.local"
export ES_PORT="9200"

echo "Creating final snapshot: ${FINAL_SNAPSHOT}"

# Use envsubst with the backup job template
export SNAPSHOT_NAME="${FINAL_SNAPSHOT}"
envsubst < "${TEMPLATES_DIR}/es-backup-job.yml" > "${STATE_DIR}/final-backup-job.yml"
kubectl apply -f "${STATE_DIR}/final-backup-job.yml"

# Wait for job
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${YELLOW}⚠ Final backup may have issues, check manually${NC}"
}

# Save final snapshot name
echo "FINAL_SNAPSHOT=${FINAL_SNAPSHOT}" >> "${STATE_DIR}/elasticsearch.env"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Freeze Complete!${NC}"
echo "============================================================================="
echo ""
echo -e "${YELLOW}⚠ Camunda is now DOWN. Proceed quickly with restore.${NC}"
echo ""
echo "Final snapshot: ${FINAL_SNAPSHOT}"
echo "Replica counts saved to: ${STATE_DIR}/replica-counts.env"
echo ""
echo "Next step: ./4-restore.sh"
echo ""

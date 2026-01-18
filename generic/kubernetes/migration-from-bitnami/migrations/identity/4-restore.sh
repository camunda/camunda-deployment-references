#!/bin/bash
# =============================================================================
# Identity Migration - Step 4: Restore Data to Target
# =============================================================================
# This script restores the PostgreSQL database to the target (CNPG or Managed).
# Uses templates with envsubst for YAML manifest generation.
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
echo "  Identity Migration - Step 4: Restore Data"
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
export BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"
JOB_NAME="identity-pg-restore-$(date +%Y%m%d-%H%M%S)"
export JOB_NAME
export BACKUP_FILE="${FINAL_BACKUP_FILE:-identity-db-final.dump}"

echo "Namespace: ${NAMESPACE}"
echo "Target Type: ${TARGET_DB_TYPE:-unknown}"
echo "Target Host: ${TARGET_PG_HOST:-unknown}"
echo ""

# =============================================================================
# Restore PostgreSQL Data
# =============================================================================
echo -e "${BLUE}=== Restoring PostgreSQL Database ===${NC}"
echo ""

# Ensure target is ready (if CNPG)
if [[ "${TARGET_DB_TYPE}" == "cnpg" ]]; then
    echo "Ensuring CNPG cluster is ready..."
    for _ in {1..30}; do
        STATUS=$(kubectl get cluster "${CNPG_CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        if [[ "$STATUS" == "Cluster in healthy state" ]]; then
            echo -e "${GREEN}✓ CNPG cluster is healthy${NC}"
            break
        fi
        echo "  Waiting for CNPG... Status: ${STATUS}"
        sleep 10
    done
fi

echo "Target: ${TARGET_PG_HOST}:${TARGET_PG_PORT}/${TARGET_PG_DATABASE}"
echo "Backup file: ${BACKUP_FILE}"
echo ""

# Generate and apply restore job
envsubst < "${TEMPLATES_DIR}/restore-job.yml" > "${STATE_DIR}/restore-job.yml"
kubectl apply -f "${STATE_DIR}/restore-job.yml"

echo "Waiting for restore to complete..."
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${RED}Restore job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${JOB_NAME}"
    exit 1
}

echo -e "${GREEN}✓ PostgreSQL restore completed!${NC}"

# Save restore job name
echo "RESTORE_JOB=${JOB_NAME}" >> "${STATE_DIR}/identity.env"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Restore Complete!${NC}"
echo "============================================================================="
echo ""
echo "Data restored to: ${TARGET_DB_TYPE^^}"
echo "Host: ${TARGET_PG_HOST}:${TARGET_PG_PORT}/${TARGET_PG_DATABASE}"
echo ""
echo "Next step: ./5-cutover.sh"
echo ""

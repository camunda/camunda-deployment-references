#!/bin/bash
# =============================================================================
# Orchestration Migration - Step 1: Backup Elasticsearch
# =============================================================================
# Creates a snapshot of Elasticsearch data using the snapshot API.
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
echo "  Orchestration Migration - Step 1: Backup Elasticsearch"
echo "============================================================================="
echo ""

# -----------------------------------------------------------------------------
# Load state from introspection
# -----------------------------------------------------------------------------
if [[ ! -f "${STATE_DIR}/elasticsearch.env" ]]; then
    echo -e "${RED}Error: Introspection state not found. Run ./0-introspect.sh first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${STATE_DIR}/elasticsearch.env"

# -----------------------------------------------------------------------------
# Set environment variables for templates
# -----------------------------------------------------------------------------
export NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
export BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup}"
export STORAGE_SIZE="${ES_STORAGE_SIZE:-50Gi}"
export STORAGE_CLASS="${ES_STORAGE_CLASS:-}"
SNAPSHOT_NAME="migration-$(date +%Y%m%d-%H%M%S)"
export SNAPSHOT_NAME
export SNAPSHOT_REPO="migration_repo"
export JOB_NAME="es-backup-${SNAPSHOT_NAME}"

# ES connection
export ES_HOST="${ES_STS_NAME/-master/}.${NAMESPACE}.svc.cluster.local"
export ES_PORT="9200"
export ES_USERNAME="${ES_USERNAME:-elastic}"
export ES_SECRET_NAME="${CAMUNDA_RELEASE_NAME:-camunda}-elasticsearch"
export ES_SECRET_KEY="elasticsearch-password"

echo "Namespace: ${NAMESPACE}"
echo "Elasticsearch: ${ES_HOST}:${ES_PORT}"
echo "Backup PVC: ${BACKUP_PVC}"
echo "Snapshot: ${SNAPSHOT_NAME}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Ensure backup PVC exists
# -----------------------------------------------------------------------------
echo -e "${BLUE}=== Checking Backup PVC ===${NC}"

if ! kubectl get pvc "${BACKUP_PVC}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}Creating backup PVC...${NC}"
    envsubst < "${TEMPLATES_DIR}/backup-pvc.yml" | kubectl apply -f -
    echo -e "${GREEN}✓ Backup PVC created${NC}"
else
    echo -e "${GREEN}✓ Backup PVC exists${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 2: Create and apply backup job
# -----------------------------------------------------------------------------
echo -e "${BLUE}=== Creating Elasticsearch Backup Job ===${NC}"
echo ""

# Generate job manifest for reference
envsubst < "${TEMPLATES_DIR}/es-backup-job.yml" > "${STATE_DIR}/backup-job.yml"

# Apply job
kubectl apply -f "${STATE_DIR}/backup-job.yml"

echo ""
echo -e "${BLUE}=== Waiting for Backup to Complete ===${NC}"
echo ""

# Wait for job to complete
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${RED}Backup job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${JOB_NAME}"
    exit 1
}

echo ""
echo -e "${GREEN}✓ Backup completed successfully!${NC}"

# -----------------------------------------------------------------------------
# Save state for next steps
# -----------------------------------------------------------------------------
cat >> "${STATE_DIR}/elasticsearch.env" <<EOF
SNAPSHOT_NAME=${SNAPSHOT_NAME}
SNAPSHOT_REPO=${SNAPSHOT_REPO}
BACKUP_PVC=${BACKUP_PVC}
BACKUP_JOB_NAME=${JOB_NAME}
EOF

echo ""
echo "============================================================================="
echo -e "${GREEN}  Backup Complete!${NC}"
echo "============================================================================="
echo ""
echo "Snapshot: ${SNAPSHOT_NAME}"
echo "Backup PVC: ${BACKUP_PVC}"
echo ""
echo "Next step: ./2-deploy-target.sh"
echo ""

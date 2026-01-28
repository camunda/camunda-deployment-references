#!/bin/bash
# =============================================================================
# Identity Migration - Step 1: Backup Identity Database
# =============================================================================
# This script backs up the Identity PostgreSQL database using pg_dump.
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
echo "  Identity Migration - Step 1: Backup Database"
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
if [[ ! -f "${STATE_DIR}/identity.env" ]]; then
    echo -e "${RED}Error: Introspection state not found. Run ./0-introspect.sh first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${STATE_DIR}/identity.env"

# -----------------------------------------------------------------------------
# Set environment variables for templates
# -----------------------------------------------------------------------------
export NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
export RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
export BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"
export BACKUP_STORAGE_SIZE="${PG_STORAGE_SIZE:-50Gi}"
export STORAGE_CLASS="${PG_STORAGE_CLASS:-}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
export TIMESTAMP

export PG_HOST="${PG_STS_NAME}.${NAMESPACE}.svc.cluster.local"
export PG_PORT="5432"
export BACKUP_FILE="identity-db-${TIMESTAMP}.dump"
export JOB_NAME="identity-pg-backup-${TIMESTAMP}"
export PG_SECRET_NAME="${PG_STS_NAME}"
export PG_SECRET_KEY="postgres-password"

echo "Namespace: ${NAMESPACE}"
echo "PostgreSQL StatefulSet: ${PG_STS_NAME}"
echo "Backup PVC: ${BACKUP_PVC}"
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
echo -e "${BLUE}=== Creating PostgreSQL Backup Job ===${NC}"
echo ""

# Generate job manifest for reference
envsubst < "${TEMPLATES_DIR}/backup-job.yml" > "${STATE_DIR}/backup-job.yml"

# Apply job
kubectl apply -f "${STATE_DIR}/backup-job.yml"

echo "Waiting for backup to complete..."
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${RED}Backup job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${JOB_NAME}"
    exit 1
}

echo -e "${GREEN}✓ Backup completed successfully!${NC}"

# -----------------------------------------------------------------------------
# Save state for next steps
# -----------------------------------------------------------------------------
cat >> "${STATE_DIR}/identity.env" <<EOF

# Backup info
export BACKUP_FILE="${BACKUP_FILE}"
export BACKUP_JOB="${JOB_NAME}"
export BACKUP_TIMESTAMP="${TIMESTAMP}"
EOF

echo ""
echo "============================================================================="
echo -e "${GREEN}  Backup Complete!${NC}"
echo "============================================================================="
echo ""
echo "Backup location: ${BACKUP_PVC}:/backup/identity/"
echo "Backup file: ${BACKUP_FILE}"
echo ""
echo "Next step: ./2-deploy-target.sh"
echo ""

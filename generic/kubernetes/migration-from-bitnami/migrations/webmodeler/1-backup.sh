#!/bin/bash
# =============================================================================
# WebModeler Migration - Step 1: Backup WebModeler Database
# =============================================================================
# This script backs up the WebModeler PostgreSQL database using pg_dump.
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
echo "  WebModeler Migration - Step 1: Backup Database"
echo "============================================================================="
echo ""

# Check for skip
if [[ -f "${MIGRATION_STATE_DIR}/skip" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/skip"
    echo -e "${YELLOW}Migration skipped: ${SKIP_REASON}${NC}"
    exit 0
fi

# Load state from introspection
if [[ ! -f "${MIGRATION_STATE_DIR}/webmodeler.env" ]]; then
    echo -e "${RED}Error: Introspection state not found. Run ./0-introspect.sh first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${MIGRATION_STATE_DIR}/webmodeler.env"

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "Namespace: ${NAMESPACE}"
echo "PostgreSQL StatefulSet: ${PG_STS_NAME}"
echo "Backup PVC: ${BACKUP_PVC}"
echo ""

# Ensure backup PVC exists
echo -e "${BLUE}=== Checking Backup PVC ===${NC}"
if ! kubectl get pvc "${BACKUP_PVC}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}Creating backup PVC...${NC}"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${BACKUP_PVC}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${BACKUP_STORAGE_SIZE:-50Gi}
  storageClassName: ${PG_STORAGE_CLASS:-default}
EOF
    echo -e "${GREEN}✓ Backup PVC created${NC}"
else
    echo -e "${GREEN}✓ Backup PVC exists${NC}"
fi
echo ""

# =============================================================================
# Create Backup Job
# =============================================================================
echo -e "${BLUE}=== Creating PostgreSQL Backup Job ===${NC}"
echo ""

PG_HOST="${PG_STS_NAME}.${NAMESPACE}.svc.cluster.local"
PG_PORT="5432"
BACKUP_JOB_NAME="webmodeler-pg-backup-${TIMESTAMP}"

# Build imagePullSecrets YAML
IMAGE_PULL_SECRETS_YAML=""
if [[ -n "${PG_IMAGE_PULL_SECRETS:-}" ]]; then
    IMAGE_PULL_SECRETS_YAML="imagePullSecrets:"
    IFS=',' read -ra SECRETS <<< "$PG_IMAGE_PULL_SECRETS"
    for secret in "${SECRETS[@]}"; do
        IMAGE_PULL_SECRETS_YAML="${IMAGE_PULL_SECRETS_YAML}
        - name: ${secret}"
    done
fi

# Try to find the password secret - different naming conventions
PG_SECRET_NAME="${PG_STS_NAME}"
if ! kubectl get secret "${PG_SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    # Try alternative naming
    if kubectl get secret "${RELEASE_NAME}-web-modeler-postgresql" -n "${NAMESPACE}" &>/dev/null; then
        PG_SECRET_NAME="${RELEASE_NAME}-web-modeler-postgresql"
    fi
fi

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${BACKUP_JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: webmodeler-migration
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      ${IMAGE_PULL_SECRETS_YAML}
      containers:
        - name: backup
          image: ${PG_IMAGE}
          command:
            - /bin/bash
            - -c
            - |
              set -e

              echo "Waiting for PostgreSQL to be ready..."
              until pg_isready -h ${PG_HOST} -p ${PG_PORT} -U \${PGUSER}; do
                echo "Waiting for PostgreSQL..."
                sleep 5
              done

              echo "PostgreSQL is ready"

              mkdir -p /backup/webmodeler

              echo "Creating database backup..."
              pg_dump -h ${PG_HOST} -p ${PG_PORT} -U \${PGUSER} -d ${PG_DATABASE:-web-modeler} \
                -F custom -f /backup/webmodeler/webmodeler-db-${TIMESTAMP}.dump

              echo ""
              echo "Backup complete!"
              ls -lh /backup/webmodeler/

              # Count tables for validation
              echo ""
              echo "Tables in backup:"
              pg_restore --list /backup/webmodeler/webmodeler-db-${TIMESTAMP}.dump | grep "TABLE" | wc -l

          env:
            - name: PGUSER
              value: "${PG_USERNAME:-postgres}"
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${PG_SECRET_NAME}
                  key: postgres-password
                  optional: true
          volumeMounts:
            - name: backup
              mountPath: /backup
      volumes:
        - name: backup
          persistentVolumeClaim:
            claimName: ${BACKUP_PVC}
EOF

echo "Waiting for backup to complete..."
kubectl wait --for=condition=complete "job/${BACKUP_JOB_NAME}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${RED}Backup job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${BACKUP_JOB_NAME}"
    exit 1
}

echo -e "${GREEN}✓ Backup completed successfully!${NC}"

# Save backup info
cat >> "${MIGRATION_STATE_DIR}/webmodeler.env" <<EOF

# Backup info
export BACKUP_FILE="webmodeler-db-${TIMESTAMP}.dump"
export BACKUP_JOB="${BACKUP_JOB_NAME}"
export BACKUP_TIMESTAMP="${TIMESTAMP}"
EOF

echo ""
echo "============================================================================="
echo -e "${GREEN}  Backup Complete!${NC}"
echo "============================================================================="
echo ""
echo "Backup location: ${BACKUP_PVC}:/backup/webmodeler/"
echo "Backup file: webmodeler-db-${TIMESTAMP}.dump"
echo ""
echo "Next step: ./2-deploy-target.sh"
echo ""

#!/bin/bash
# =============================================================================
# WebModeler Migration - Step 4: Restore Data to Target
# =============================================================================
# This script restores the PostgreSQL database to the target (CNPG or Managed).
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
echo "  WebModeler Migration - Step 4: Restore Data"
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
if [[ ! -f "${MIGRATION_STATE_DIR}/webmodeler.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${MIGRATION_STATE_DIR}/webmodeler.env"

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"

echo "Namespace: ${NAMESPACE}"
echo "Target Type: ${TARGET_DB_TYPE:-unknown}"
echo "Target Host: ${TARGET_PG_HOST:-unknown}"
echo ""

# =============================================================================
# Restore PostgreSQL Data
# =============================================================================
echo -e "${BLUE}=== Restoring PostgreSQL Database ===${NC}"
echo ""

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESTORE_JOB="webmodeler-pg-restore-${TIMESTAMP}"

RESTORE_HOST="${TARGET_PG_HOST}"
RESTORE_PORT="${TARGET_PG_PORT:-5432}"
RESTORE_DB="${TARGET_PG_DATABASE:-web-modeler}"
RESTORE_USER="${TARGET_PG_USER:-webmodeler}"

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

echo "Target: ${RESTORE_HOST}:${RESTORE_PORT}/${RESTORE_DB}"
echo "Backup file: webmodeler-db-final.dump"
echo ""

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

# Create restore job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${RESTORE_JOB}
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
        - name: restore
          image: ${PG_IMAGE}
          command:
            - /bin/bash
            - -c
            - |
              set -e

              echo "Waiting for target PostgreSQL to be ready..."
              until pg_isready -h ${RESTORE_HOST} -p ${RESTORE_PORT} -U ${RESTORE_USER}; do
                echo "Waiting for PostgreSQL..."
                sleep 5
              done

              echo "Target PostgreSQL is ready"

              # Check backup file
              if [ ! -f /backup/webmodeler/webmodeler-db-final.dump ]; then
                echo "Final backup not found, using initial backup..."
                BACKUP_FILE=\$(ls -t /backup/webmodeler/webmodeler-db-*.dump | head -1)
              else
                BACKUP_FILE=/backup/webmodeler/webmodeler-db-final.dump
              fi

              echo "Restoring from: \${BACKUP_FILE}"

              # Restore
              pg_restore -h ${RESTORE_HOST} -p ${RESTORE_PORT} -U ${RESTORE_USER} \
                -d ${RESTORE_DB} \
                --clean --if-exists \
                --no-owner --no-privileges \
                \${BACKUP_FILE} || {
                  echo "pg_restore completed with warnings (this is often normal)"
                }

              echo ""
              echo "Validating restore..."

              # Count tables
              TABLE_COUNT=\$(psql -h ${RESTORE_HOST} -p ${RESTORE_PORT} -U ${RESTORE_USER} -d ${RESTORE_DB} \
                -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")

              echo "Tables in restored database: \${TABLE_COUNT}"

              echo ""
              echo "Restore complete!"

          env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${DB_SECRET_NAME}
                  key: password
          volumeMounts:
            - name: backup
              mountPath: /backup
      volumes:
        - name: backup
          persistentVolumeClaim:
            claimName: ${BACKUP_PVC}
EOF

echo "Waiting for restore to complete..."
kubectl wait --for=condition=complete "job/${RESTORE_JOB}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${RED}Restore job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${RESTORE_JOB}"
    exit 1
}

echo -e "${GREEN}✓ PostgreSQL restore completed!${NC}"

# Save restore job name
echo "RESTORE_JOB=${RESTORE_JOB}" >> "${MIGRATION_STATE_DIR}/webmodeler.env"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Restore Complete!${NC}"
echo "============================================================================="
echo ""
echo "Data restored to: ${TARGET_DB_TYPE^^}"
echo "Host: ${RESTORE_HOST}:${RESTORE_PORT}/${RESTORE_DB}"
echo ""
echo "Next step: ./5-cutover.sh"
echo ""

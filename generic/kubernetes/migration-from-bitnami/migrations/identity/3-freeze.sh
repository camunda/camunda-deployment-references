#!/bin/bash
# =============================================================================
# Identity Migration - Step 3: Freeze Identity Component
# =============================================================================
# This script scales down Identity to stop writes before final data migration.
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
echo "  Identity Migration - Step 3: Freeze Component"
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
if [[ ! -f "${MIGRATION_STATE_DIR}/identity.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${MIGRATION_STATE_DIR}/identity.env"

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

echo -e "${YELLOW}⚠ WARNING: This will cause Identity downtime!${NC}"
echo ""
read -r -p "Continue with freeze? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Freeze cancelled."
    exit 0
fi
echo ""

# =============================================================================
# Save Current Replica Count
# =============================================================================
echo -e "${BLUE}=== Saving Replica Count ===${NC}"
echo ""

IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"
IDENTITY_REPLICAS=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')

echo "Identity replicas: ${IDENTITY_REPLICAS}"

cat > "${MIGRATION_STATE_DIR}/replica-counts.env" <<EOF
export IDENTITY_SAVED_REPLICAS="${IDENTITY_REPLICAS}"
EOF

echo -e "${GREEN}✓ Replica count saved${NC}"
echo ""

# =============================================================================
# Scale Down Identity
# =============================================================================
echo -e "${BLUE}=== Scaling Down Identity ===${NC}"
echo ""

kubectl scale deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" --replicas=0

echo "Waiting for Identity pods to terminate..."
kubectl wait --for=delete pod -l "app.kubernetes.io/name=identity,app.kubernetes.io/instance=${RELEASE_NAME}" \
    -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true

echo -e "${GREEN}✓ Identity scaled to 0${NC}"
echo ""

# =============================================================================
# Final Backup Sync
# =============================================================================
echo -e "${BLUE}=== Final PostgreSQL Backup Sync ===${NC}"
echo ""

PG_HOST="${PG_STS_NAME}.${NAMESPACE}.svc.cluster.local"
PG_PORT="5432"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FINAL_BACKUP_JOB="identity-pg-final-backup-${TIMESTAMP}"

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

echo "Creating final database backup with no active connections..."

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${FINAL_BACKUP_JOB}
  namespace: ${NAMESPACE}
  labels:
    app: identity-migration
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

              echo "Creating final database backup..."

              mkdir -p /backup/identity

              pg_dump -h ${PG_HOST} -p ${PG_PORT} -U \${PGUSER} -d ${PG_DATABASE:-identity} \
                -F custom -f /backup/identity/identity-db-final.dump

              echo "Final backup complete!"
              ls -lh /backup/identity/

          env:
            - name: PGUSER
              value: "${PG_USERNAME:-postgres}"
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${PG_STS_NAME}
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

echo "Waiting for final backup to complete..."
kubectl wait --for=condition=complete "job/${FINAL_BACKUP_JOB}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${RED}Final backup job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${FINAL_BACKUP_JOB}"
    exit 1
}

echo -e "${GREEN}✓ Final PostgreSQL backup completed!${NC}"

# Update state
echo "FINAL_BACKUP_FILE=identity-db-final.dump" >> "${MIGRATION_STATE_DIR}/identity.env"
echo "FINAL_BACKUP_JOB=${FINAL_BACKUP_JOB}" >> "${MIGRATION_STATE_DIR}/identity.env"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Freeze Complete!${NC}"
echo "============================================================================="
echo ""
echo "Identity: 0 replicas (was ${IDENTITY_REPLICAS})"
echo "Final backup: identity-db-final.dump"
echo ""
echo -e "${YELLOW}⚠ Identity is now DOWN!${NC}"
echo ""
echo "Next step: ./4-restore.sh"
echo ""

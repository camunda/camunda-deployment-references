#!/bin/bash
# =============================================================================
# WebModeler Migration - Step 3: Freeze WebModeler Components
# =============================================================================
# This script scales down WebModeler to stop writes before final data migration.
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
echo "  WebModeler Migration - Step 3: Freeze Components"
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
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

echo -e "${YELLOW}⚠ WARNING: This will cause WebModeler downtime!${NC}"
echo ""
read -r -p "Continue with freeze? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Freeze cancelled."
    exit 0
fi
echo ""

# =============================================================================
# Save Current Replica Counts
# =============================================================================
echo -e "${BLUE}=== Saving Replica Counts ===${NC}"
echo ""

# Get replica counts for all WebModeler components
RESTAPI_REPLICAS=0
WEBAPP_REPLICAS=0
WEBSOCKETS_REPLICAS=0

if kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" &>/dev/null; then
    RESTAPI_REPLICAS=$(kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
    echo "RestAPI replicas: ${RESTAPI_REPLICAS}"
fi

if kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" &>/dev/null; then
    WEBAPP_REPLICAS=$(kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
    echo "Webapp replicas: ${WEBAPP_REPLICAS}"
fi

if kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" &>/dev/null; then
    WEBSOCKETS_REPLICAS=$(kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
    echo "WebSockets replicas: ${WEBSOCKETS_REPLICAS}"
fi

cat > "${MIGRATION_STATE_DIR}/replica-counts.env" <<EOF
export RESTAPI_SAVED_REPLICAS="${RESTAPI_REPLICAS}"
export WEBAPP_SAVED_REPLICAS="${WEBAPP_REPLICAS}"
export WEBSOCKETS_SAVED_REPLICAS="${WEBSOCKETS_REPLICAS}"
EOF

echo -e "${GREEN}✓ Replica counts saved${NC}"
echo ""

# =============================================================================
# Scale Down WebModeler Components
# =============================================================================
echo -e "${BLUE}=== Scaling Down WebModeler ===${NC}"
echo ""

# Scale down RestAPI first (handles database connections)
if kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" &>/dev/null; then
    kubectl scale deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" --replicas=0
    echo "Scaled down RestAPI"
fi

# Scale down Webapp
if kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" &>/dev/null; then
    kubectl scale deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" --replicas=0
    echo "Scaled down Webapp"
fi

# Scale down WebSockets
if kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" &>/dev/null; then
    kubectl scale deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" --replicas=0
    echo "Scaled down WebSockets"
fi

echo ""
echo "Waiting for WebModeler pods to terminate..."
kubectl wait --for=delete pod -l "app.kubernetes.io/component=web-modeler,app.kubernetes.io/instance=${RELEASE_NAME}" \
    -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true

echo -e "${GREEN}✓ WebModeler scaled to 0${NC}"
echo ""

# =============================================================================
# Final Backup Sync
# =============================================================================
echo -e "${BLUE}=== Final PostgreSQL Backup Sync ===${NC}"
echo ""

PG_HOST="${PG_STS_NAME}.${NAMESPACE}.svc.cluster.local"
PG_PORT="5432"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FINAL_BACKUP_JOB="webmodeler-pg-final-backup-${TIMESTAMP}"

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

# Try to find the password secret
PG_SECRET_NAME="${PG_STS_NAME}"
if ! kubectl get secret "${PG_SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    if kubectl get secret "${RELEASE_NAME}-web-modeler-postgresql" -n "${NAMESPACE}" &>/dev/null; then
        PG_SECRET_NAME="${RELEASE_NAME}-web-modeler-postgresql"
    fi
fi

echo "Creating final database backup with no active connections..."

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${FINAL_BACKUP_JOB}
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

              echo "Creating final database backup..."

              mkdir -p /backup/webmodeler

              pg_dump -h ${PG_HOST} -p ${PG_PORT} -U \${PGUSER} -d ${PG_DATABASE:-web-modeler} \
                -F custom -f /backup/webmodeler/webmodeler-db-final.dump

              echo "Final backup complete!"
              ls -lh /backup/webmodeler/

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

echo "Waiting for final backup to complete..."
kubectl wait --for=condition=complete "job/${FINAL_BACKUP_JOB}" -n "${NAMESPACE}" --timeout=1800s || {
    echo -e "${RED}Final backup job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${FINAL_BACKUP_JOB}"
    exit 1
}

echo -e "${GREEN}✓ Final backup completed!${NC}"

# Save final backup info
cat >> "${MIGRATION_STATE_DIR}/webmodeler.env" <<EOF

# Final backup
export FINAL_BACKUP_FILE="webmodeler-db-final.dump"
export FINAL_BACKUP_JOB="${FINAL_BACKUP_JOB}"
EOF

echo ""
echo "============================================================================="
echo -e "${GREEN}  Freeze Complete!${NC}"
echo "============================================================================="
echo ""
echo "WebModeler components scaled to 0."
echo "Final backup: webmodeler-db-final.dump"
echo ""
echo "Next step: ./4-restore.sh"
echo ""

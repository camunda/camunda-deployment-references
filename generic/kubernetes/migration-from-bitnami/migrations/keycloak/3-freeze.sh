#!/bin/bash
# =============================================================================
# Keycloak Migration - Step 3: Freeze Keycloak and Identity
# =============================================================================
# This script scales down Keycloak and Identity to stop writes before
# the final data migration.
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
echo "  Keycloak Migration - Step 3: Freeze Components"
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
if [[ ! -f "${MIGRATION_STATE_DIR}/keycloak.env" ]]; then
    echo -e "${RED}Error: State not found. Run previous steps first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${MIGRATION_STATE_DIR}/keycloak.env"

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

echo -e "${YELLOW}⚠ WARNING: This will cause authentication downtime!${NC}"
echo ""
echo "The following components will be scaled to 0:"
echo "  - Keycloak (${KC_STS_NAME})"
echo "  - Camunda Identity (if deployed)"
echo ""
read -r -p "Continue with freeze? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Freeze cancelled."
    exit 0
fi
echo ""

# =============================================================================
# Step 1: Save Current Replica Counts
# =============================================================================
echo -e "${BLUE}=== Saving Replica Counts ===${NC}"
echo ""

# Get Keycloak replica count
KC_CURRENT_REPLICAS=$(kubectl get statefulset "${KC_STS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
echo "Keycloak replicas: ${KC_CURRENT_REPLICAS}"

# Get Identity replica count (if exists)
IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"
IDENTITY_CURRENT_REPLICAS=0
if kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
    IDENTITY_CURRENT_REPLICAS=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
    echo "Identity replicas: ${IDENTITY_CURRENT_REPLICAS}"
else
    echo "Identity deployment not found (may not be installed)"
fi

# Save replica counts for rollback
cat > "${MIGRATION_STATE_DIR}/replica-counts.env" <<EOF
# Replica counts before freeze
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

export KC_SAVED_REPLICAS="${KC_CURRENT_REPLICAS}"
export IDENTITY_SAVED_REPLICAS="${IDENTITY_CURRENT_REPLICAS}"
EOF

echo -e "${GREEN}✓ Replica counts saved${NC}"
echo ""

# =============================================================================
# Step 2: Scale Down Keycloak
# =============================================================================
echo -e "${BLUE}=== Scaling Down Keycloak ===${NC}"
echo ""

kubectl scale statefulset "${KC_STS_NAME}" -n "${NAMESPACE}" --replicas=0

echo "Waiting for Keycloak pods to terminate..."
kubectl wait --for=delete pod -l "app.kubernetes.io/name=keycloak,app.kubernetes.io/instance=${RELEASE_NAME}" \
    -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true

echo -e "${GREEN}✓ Keycloak scaled to 0${NC}"
echo ""

# =============================================================================
# Step 3: Scale Down Identity (if exists)
# =============================================================================
if kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${BLUE}=== Scaling Down Identity ===${NC}"
    echo ""

    kubectl scale deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" --replicas=0

    echo "Waiting for Identity pods to terminate..."
    kubectl wait --for=delete pod -l "app.kubernetes.io/name=identity,app.kubernetes.io/instance=${RELEASE_NAME}" \
        -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true

    echo -e "${GREEN}✓ Identity scaled to 0${NC}"
    echo ""
fi

# =============================================================================
# Step 4: Final Backup Sync (if integrated PostgreSQL)
# =============================================================================
if [[ "$PG_MODE" == "integrated" ]]; then
    echo -e "${BLUE}=== Final PostgreSQL Backup Sync ===${NC}"
    echo ""

    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/postgres.env"

    PG_HOST="${PG_STS_NAME}.${NAMESPACE}.svc.cluster.local"
    PG_PORT="5432"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    FINAL_BACKUP_JOB="keycloak-pg-final-backup-${TIMESTAMP}"

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

              mkdir -p /backup/keycloak

              pg_dump -h ${PG_HOST} -p ${PG_PORT} -U \${PGUSER} -d ${PG_DATABASE:-keycloak} \
                -F custom -f /backup/keycloak/keycloak-db-final.dump

              echo "Final backup complete!"
              ls -lh /backup/keycloak/

          env:
            - name: PGUSER
              value: "${PG_USERNAME:-postgres}"
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${RELEASE_NAME}-keycloak-postgresql
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

    # Update state with final backup info
    echo "FINAL_BACKUP_FILE=keycloak-db-final.dump" >> "${MIGRATION_STATE_DIR}/keycloak.env"
    echo "FINAL_BACKUP_JOB=${FINAL_BACKUP_JOB}" >> "${MIGRATION_STATE_DIR}/keycloak.env"
fi

echo ""
echo "============================================================================="
echo -e "${GREEN}  Freeze Complete!${NC}"
echo "============================================================================="
echo ""
echo "Components frozen:"
echo "  - Keycloak: 0 replicas (was ${KC_CURRENT_REPLICAS})"
if [[ $IDENTITY_CURRENT_REPLICAS -gt 0 ]]; then
    echo "  - Identity: 0 replicas (was ${IDENTITY_CURRENT_REPLICAS})"
fi
if [[ "$PG_MODE" == "integrated" ]]; then
    echo ""
    echo "Final backup: keycloak-db-final.dump"
fi
echo ""
echo -e "${YELLOW}⚠ Authentication is now DOWN!${NC}"
echo ""
echo "Next step: ./4-restore.sh"
echo ""

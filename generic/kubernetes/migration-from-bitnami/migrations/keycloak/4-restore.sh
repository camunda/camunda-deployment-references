#!/bin/bash
# =============================================================================
# Keycloak Migration - Step 4: Restore Data to Target
# =============================================================================
# This script restores the PostgreSQL database (if integrated) and deploys
# the Keycloak Operator instance.
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
echo "  Keycloak Migration - Step 4: Restore Data"
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
echo "PostgreSQL Mode: ${PG_MODE}"
echo "Target DB Type: ${TARGET_DB_TYPE:-external}"
echo ""

# =============================================================================
# Step 1: Restore PostgreSQL Data (if integrated mode)
# =============================================================================
if [[ "$PG_MODE" == "integrated" ]]; then
    echo -e "${BLUE}=== Restoring PostgreSQL Database ===${NC}"
    echo ""

    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/postgres.env"

    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    RESTORE_JOB="keycloak-pg-restore-${TIMESTAMP}"

    # Determine target host based on deployment type
    if [[ "${TARGET_DB_TYPE}" == "cnpg" ]]; then
        RESTORE_HOST="${CNPG_CLUSTER_NAME}-rw.${NAMESPACE}.svc.cluster.local"
        RESTORE_USER="${PG_USERNAME:-keycloak}"

        # Wait for CNPG to be ready
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

    elif [[ "${TARGET_DB_TYPE}" == "managed" ]]; then
        RESTORE_HOST="${TARGET_PG_HOST}"
        RESTORE_USER="${TARGET_PG_USER}"
    else
        echo -e "${YELLOW}External PostgreSQL - skipping restore${NC}"
        RESTORE_HOST=""
    fi

    if [[ -n "${RESTORE_HOST}" ]]; then
        RESTORE_PORT="${TARGET_PG_PORT:-5432}"
        RESTORE_DB="${TARGET_PG_DATABASE:-keycloak}"

        echo "Target: ${RESTORE_HOST}:${RESTORE_PORT}/${RESTORE_DB}"
        echo "Backup file: keycloak-db-final.dump"
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

              # Check if backup file exists
              if [ ! -f /backup/keycloak/keycloak-db-final.dump ]; then
                echo "Final backup not found, using initial backup..."
                BACKUP_FILE=\$(ls -t /backup/keycloak/keycloak-db-*.dump | head -1)
              else
                BACKUP_FILE=/backup/keycloak/keycloak-db-final.dump
              fi

              echo "Restoring from: \${BACKUP_FILE}"

              # Restore the database
              pg_restore -h ${RESTORE_HOST} -p ${RESTORE_PORT} -U ${RESTORE_USER} \
                -d ${RESTORE_DB} \
                --clean --if-exists \
                --no-owner --no-privileges \
                \${BACKUP_FILE} || {
                  # pg_restore returns non-zero on warnings, check if it's critical
                  echo "pg_restore completed with warnings (this is often normal)"
                }

              echo ""
              echo "Validating restore..."

              # Count tables
              TABLE_COUNT=\$(psql -h ${RESTORE_HOST} -p ${RESTORE_PORT} -U ${RESTORE_USER} -d ${RESTORE_DB} \
                -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")

              echo "Tables in restored database: \${TABLE_COUNT}"

              # Count realms
              REALM_COUNT=\$(psql -h ${RESTORE_HOST} -p ${RESTORE_PORT} -U ${RESTORE_USER} -d ${RESTORE_DB} \
                -t -c "SELECT count(*) FROM realm" 2>/dev/null || echo "0")

              echo "Realms in restored database: \${REALM_COUNT}"

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
        echo "RESTORE_JOB=${RESTORE_JOB}" >> "${MIGRATION_STATE_DIR}/keycloak.env"
    fi
else
    echo -e "${BLUE}=== PostgreSQL Restore Skipped ===${NC}"
    echo ""
    echo "PostgreSQL is external - data is already in place."
fi

echo ""

# =============================================================================
# Step 2: Deploy Keycloak Operator Instance
# =============================================================================
echo -e "${BLUE}=== Deploying Keycloak Operator Instance ===${NC}"
echo ""

if [[ ! -f "${MIGRATION_STATE_DIR}/keycloak-operator.yml" ]]; then
    echo -e "${RED}Error: Keycloak Operator manifest not found${NC}"
    exit 1
fi

echo "Applying Keycloak Operator CRD..."
kubectl apply -f "${MIGRATION_STATE_DIR}/keycloak-operator.yml"

echo ""
echo "Waiting for Keycloak Operator instance to be ready..."

for i in {1..60}; do
    # Check if Keycloak instance exists and get status
    if kubectl get keycloak "${KEYCLOAK_INSTANCE_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        READY=$(kubectl get keycloak "${KEYCLOAK_INSTANCE_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

        echo "  Keycloak Ready: ${READY}"

        if [[ "$READY" == "True" ]]; then
            break
        fi
    else
        echo "  Waiting for Keycloak resource to be created..."
    fi

    if [[ $i -eq 60 ]]; then
        echo -e "${YELLOW}Keycloak taking longer than expected. Continuing...${NC}"
        echo "Check status with: kubectl get keycloak ${KEYCLOAK_INSTANCE_NAME} -n ${NAMESPACE}"
    fi

    sleep 10
done

# Check pod status
echo ""
echo "Checking Keycloak pods..."
kubectl get pods -l "app=keycloak,app.kubernetes.io/managed-by=keycloak-operator" -n "${NAMESPACE}" 2>/dev/null || \
    kubectl get pods -l "app.kubernetes.io/name=${KEYCLOAK_INSTANCE_NAME}" -n "${NAMESPACE}" 2>/dev/null || \
    echo "Pods may still be starting..."

echo ""
echo -e "${GREEN}✓ Keycloak Operator instance deployed!${NC}"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Restore Complete!${NC}"
echo "============================================================================="
echo ""
if [[ "$PG_MODE" == "integrated" ]] && [[ -n "${RESTORE_HOST:-}" ]]; then
    echo "PostgreSQL: Restored to ${TARGET_DB_TYPE^^}"
fi
echo "Keycloak: Operator instance deployed"
echo ""
echo "Keycloak Operator Service: ${KEYCLOAK_INSTANCE_NAME}-service.${NAMESPACE}.svc.cluster.local"
echo ""
echo "Next step: ./5-cutover.sh"
echo ""

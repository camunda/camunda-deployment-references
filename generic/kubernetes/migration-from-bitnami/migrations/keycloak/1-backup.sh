#!/bin/bash
# =============================================================================
# Keycloak Migration - Step 1: Backup Keycloak Data
# =============================================================================
# This script backs up Keycloak realm configuration and (if integrated mode)
# the PostgreSQL database.
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
echo "  Keycloak Migration - Step 1: Backup"
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
if [[ ! -f "${MIGRATION_STATE_DIR}/keycloak.env" ]]; then
    echo -e "${RED}Error: Introspection state not found. Run ./0-introspect.sh first${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source "${MIGRATION_STATE_DIR}/keycloak.env"

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
BACKUP_PVC="${BACKUP_PVC_NAME:-migration-backup-pvc}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "PostgreSQL Mode: ${PG_MODE}"
echo "Backup PVC: ${BACKUP_PVC}"
echo ""

# Ensure backup PVC exists
echo -e "${BLUE}=== Checking Backup PVC ===${NC}"
if ! kubectl get pvc "${BACKUP_PVC}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}Creating backup PVC...${NC}"
    STORAGE_CLASS="${PG_STORAGE_CLASS:-default}"
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
  storageClassName: ${STORAGE_CLASS}
EOF
    echo -e "${GREEN}✓ Backup PVC created${NC}"
else
    echo -e "${GREEN}✓ Backup PVC exists${NC}"
fi
echo ""

# =============================================================================
# Step 1: Export Keycloak Realm Configuration
# =============================================================================
echo -e "${BLUE}=== Exporting Keycloak Realm Configuration ===${NC}"
echo ""

# Get Keycloak service endpoint
KC_SERVICE="${RELEASE_NAME}-keycloak"
KC_HOST="${KC_SERVICE}.${NAMESPACE}.svc.cluster.local"
KC_PORT="80"

# Get admin credentials
KC_ADMIN_USER=$(kubectl get secret "${RELEASE_NAME}-keycloak" -n "${NAMESPACE}" -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d || echo "admin")
KC_ADMIN_PASSWORD=$(kubectl get secret "${RELEASE_NAME}-keycloak" -n "${NAMESPACE}" -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "")

if [[ -z "$KC_ADMIN_PASSWORD" ]]; then
    echo -e "${YELLOW}⚠ Could not retrieve Keycloak admin password from secret${NC}"
    echo "Please enter Keycloak admin password:"
    read -r -s KC_ADMIN_PASSWORD
fi

# Create realm export job
EXPORT_JOB_NAME="keycloak-realm-export-${TIMESTAMP}"

echo "Creating realm export job..."

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${EXPORT_JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: export
          image: curlimages/curl:latest
          command:
            - /bin/sh
            - -c
            - |
              set -e

              echo "Waiting for Keycloak to be ready..."
              until curl -sf "http://${KC_HOST}:${KC_PORT}/auth/health/ready" >/dev/null 2>&1 || \
                    curl -sf "http://${KC_HOST}:${KC_PORT}/health/ready" >/dev/null 2>&1; do
                echo "Waiting for Keycloak..."
                sleep 5
              done

              echo "Keycloak is ready"

              # Detect the correct auth endpoint (Keycloak 17+ uses /realms/master, older uses /auth/realms/master)
              AUTH_ENDPOINT=""
              if curl -sf "http://${KC_HOST}:${KC_PORT}/realms/master/.well-known/openid-configuration" >/dev/null 2>&1; then
                AUTH_ENDPOINT="http://${KC_HOST}:${KC_PORT}"
              else
                AUTH_ENDPOINT="http://${KC_HOST}:${KC_PORT}/auth"
              fi

              echo "Using auth endpoint: \${AUTH_ENDPOINT}"

              # Get admin token
              echo "Getting admin token..."
              TOKEN=\$(curl -s -X POST "\${AUTH_ENDPOINT}/realms/master/protocol/openid-connect/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "username=${KC_ADMIN_USER}" \
                -d "password=${KC_ADMIN_PASSWORD}" \
                -d "grant_type=password" \
                -d "client_id=admin-cli" | jq -r '.access_token')

              if [ -z "\$TOKEN" ] || [ "\$TOKEN" = "null" ]; then
                echo "Failed to get admin token"
                exit 1
              fi

              echo "Got admin token"

              # List realms
              echo "Listing realms..."
              REALMS=\$(curl -s "\${AUTH_ENDPOINT}/admin/realms" \
                -H "Authorization: Bearer \$TOKEN" | jq -r '.[].realm')

              echo "Found realms: \$REALMS"

              # Export each realm
              mkdir -p /backup/keycloak

              for realm in \$REALMS; do
                echo "Exporting realm: \$realm"
                curl -s "\${AUTH_ENDPOINT}/admin/realms/\$realm" \
                  -H "Authorization: Bearer \$TOKEN" > "/backup/keycloak/realm-\$realm.json"

                # Also export users for non-master realms
                if [ "\$realm" != "master" ]; then
                  echo "Exporting users for realm: \$realm"
                  curl -s "\${AUTH_ENDPOINT}/admin/realms/\$realm/users?max=10000" \
                    -H "Authorization: Bearer \$TOKEN" > "/backup/keycloak/users-\$realm.json"
                fi
              done

              echo "Realm export complete!"
              ls -la /backup/keycloak/

          volumeMounts:
            - name: backup
              mountPath: /backup
      volumes:
        - name: backup
          persistentVolumeClaim:
            claimName: ${BACKUP_PVC}
EOF

echo "Waiting for realm export to complete..."
kubectl wait --for=condition=complete "job/${EXPORT_JOB_NAME}" -n "${NAMESPACE}" --timeout=600s || {
    echo -e "${RED}Realm export job failed or timed out${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${EXPORT_JOB_NAME}"
    exit 1
}

echo -e "${GREEN}✓ Realm export completed successfully!${NC}"
echo ""

# =============================================================================
# Step 2: Backup PostgreSQL (if integrated mode)
# =============================================================================
if [[ "$PG_MODE" == "integrated" ]]; then
    echo -e "${BLUE}=== Backing Up PostgreSQL Database ===${NC}"
    echo ""

    # Load PostgreSQL state
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/postgres.env"

    PG_HOST="${PG_STS_NAME}.${NAMESPACE}.svc.cluster.local"
    PG_PORT="5432"
    BACKUP_JOB_NAME="keycloak-pg-backup-${TIMESTAMP}"

    echo "PostgreSQL Host: ${PG_HOST}"
    echo "Database: ${PG_DATABASE:-keycloak}"
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

    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${BACKUP_JOB_NAME}
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

              echo "Waiting for PostgreSQL to be ready..."
              until pg_isready -h ${PG_HOST} -p ${PG_PORT} -U \${PGUSER}; do
                echo "Waiting for PostgreSQL..."
                sleep 5
              done

              echo "PostgreSQL is ready"

              mkdir -p /backup/keycloak

              echo "Creating database backup..."
              pg_dump -h ${PG_HOST} -p ${PG_PORT} -U \${PGUSER} -d ${PG_DATABASE:-keycloak} \
                -F custom -f /backup/keycloak/keycloak-db-${TIMESTAMP}.dump

              echo "Backup complete!"
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

    echo "Waiting for PostgreSQL backup to complete..."
    kubectl wait --for=condition=complete "job/${BACKUP_JOB_NAME}" -n "${NAMESPACE}" --timeout=1800s || {
        echo -e "${RED}PostgreSQL backup job failed or timed out${NC}"
        echo "Check logs with: kubectl logs -n ${NAMESPACE} job/${BACKUP_JOB_NAME}"
        exit 1
    }

    echo -e "${GREEN}✓ PostgreSQL backup completed successfully!${NC}"

    # Save backup info
    echo "PG_BACKUP_FILE=keycloak-db-${TIMESTAMP}.dump" >> "${MIGRATION_STATE_DIR}/keycloak.env"
    echo "PG_BACKUP_JOB=${BACKUP_JOB_NAME}" >> "${MIGRATION_STATE_DIR}/keycloak.env"

else
    echo -e "${BLUE}=== PostgreSQL Backup Skipped ===${NC}"
    echo ""
    echo "PostgreSQL is external - database backup is managed separately."
fi

# Save backup info
echo "REALM_EXPORT_JOB=${EXPORT_JOB_NAME}" >> "${MIGRATION_STATE_DIR}/keycloak.env"
echo "BACKUP_TIMESTAMP=${TIMESTAMP}" >> "${MIGRATION_STATE_DIR}/keycloak.env"

echo ""
echo "============================================================================="
echo -e "${GREEN}  Backup Complete!${NC}"
echo "============================================================================="
echo ""
echo "Backup location: ${BACKUP_PVC}:/backup/keycloak/"
echo "  - Realm exports: realm-*.json, users-*.json"
if [[ "$PG_MODE" == "integrated" ]]; then
    echo "  - Database dump: keycloak-db-${TIMESTAMP}.dump"
fi
echo ""
echo "Next step: ./2-deploy-target.sh"
echo ""

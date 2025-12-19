#!/bin/bash
# =============================================================================
# WebModeler Migration - Step 5: Cutover Helm Release
# =============================================================================
# This script updates the Camunda Helm release to use the new PostgreSQL.
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
echo "  WebModeler Migration - Step 5: Cutover Helm Release"
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
CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

# =============================================================================
# Backup Current Helm Values
# =============================================================================
echo -e "${BLUE}=== Backing Up Current Helm Values ===${NC}"
echo ""

helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" > "${MIGRATION_STATE_DIR}/helm-values-backup.yaml"
echo -e "${GREEN}✓ Current values saved${NC}"
echo ""

# =============================================================================
# Generate Migration Values
# =============================================================================
echo -e "${BLUE}=== Generating Migration Values ===${NC}"
echo ""

cat > "${MIGRATION_STATE_DIR}/helm-values-migration.yaml" <<EOF
# Migration values - WebModeler PostgreSQL
# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Disable Bitnami PostgreSQL for WebModeler
webModelerPostgresql:
  enabled: false

# Configure WebModeler to use new PostgreSQL
webModeler:
  restapi:
    externalDatabase:
      url: "jdbc:postgresql://${TARGET_PG_HOST}:${TARGET_PG_PORT:-5432}/${TARGET_PG_DATABASE:-web-modeler}"
      user: "${TARGET_PG_USER:-webmodeler}"
      existingSecret:
        name: "${DB_SECRET_NAME}"
      existingSecretPasswordKey: "password"
EOF

echo "Migration values:"
cat "${MIGRATION_STATE_DIR}/helm-values-migration.yaml"
echo ""

# =============================================================================
# Update Helm Release
# =============================================================================
echo -e "${BLUE}=== Updating Helm Release ===${NC}"
echo ""

echo -e "${YELLOW}This will update the Camunda Helm release to use the new PostgreSQL.${NC}"
echo ""
read -r -p "Continue with Helm upgrade? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Cutover cancelled."
    exit 0
fi
echo ""

HELM_CMD="helm upgrade ${RELEASE_NAME} camunda/camunda-platform"
HELM_CMD="${HELM_CMD} --namespace ${NAMESPACE}"
HELM_CMD="${HELM_CMD} --reuse-values"
HELM_CMD="${HELM_CMD} --values ${MIGRATION_STATE_DIR}/helm-values-migration.yaml"

if [[ -n "${CHART_VERSION}" ]]; then
    HELM_CMD="${HELM_CMD} --version ${CHART_VERSION}"
fi

HELM_CMD="${HELM_CMD} --wait --timeout 10m"

echo "Running: ${HELM_CMD}"
echo ""

eval "${HELM_CMD}"

echo ""
echo -e "${GREEN}✓ Helm release updated!${NC}"

# =============================================================================
# Verify WebModeler is Running
# =============================================================================
echo ""
echo -e "${BLUE}=== Verifying WebModeler Components ===${NC}"
echo ""

# Wait for RestAPI (it handles the database connection)
if kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" &>/dev/null; then
    echo "Waiting for WebModeler RestAPI to be ready..."
    kubectl rollout status deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" --timeout=300s || {
        echo -e "${YELLOW}RestAPI rollout taking longer than expected${NC}"
    }

    READY=$(kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    echo "RestAPI: ${READY}/${DESIRED} ready"
fi

# Check Webapp
if kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" &>/dev/null; then
    READY=$(kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    echo "Webapp: ${READY}/${DESIRED} ready"
fi

# Check WebSockets
if kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" &>/dev/null; then
    READY=$(kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    echo "WebSockets: ${READY}/${DESIRED} ready"
fi

echo ""
echo "============================================================================="
echo -e "${GREEN}  Cutover Complete!${NC}"
echo "============================================================================="
echo ""
echo "WebModeler is now using ${TARGET_DB_TYPE^^} PostgreSQL!"
echo "Host: ${TARGET_PG_HOST}:${TARGET_PG_PORT}"
echo ""
echo "Next step: ./6-validate.sh"
echo ""

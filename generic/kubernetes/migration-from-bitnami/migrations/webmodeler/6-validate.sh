#!/bin/bash
# =============================================================================
# WebModeler Migration - Step 6: Validate and Show Cleanup Commands
# =============================================================================
# This script validates the migration and shows cleanup commands.
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
echo "  WebModeler Migration - Step 6: Validate and Cleanup"
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

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

# =============================================================================
# Validation
# =============================================================================
ALL_HEALTHY=true

echo -e "${BLUE}=== Validating WebModeler Components ===${NC}"
echo ""

# Check RestAPI
if kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" &>/dev/null; then
    READY=$(kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${WEBMODELER_RESTAPI}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    if [[ "${READY}" == "${DESIRED}" ]] && [[ "${READY}" != "0" ]]; then
        echo -e "${GREEN}✓ RestAPI: ${READY}/${DESIRED} ready${NC}"
    else
        echo -e "${RED}✗ RestAPI: ${READY}/${DESIRED} ready${NC}"
        ALL_HEALTHY=false
    fi
fi

# Check Webapp
if kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" &>/dev/null; then
    READY=$(kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${WEBMODELER_WEBAPP}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    if [[ "${READY}" == "${DESIRED}" ]] && [[ "${READY}" != "0" ]]; then
        echo -e "${GREEN}✓ Webapp: ${READY}/${DESIRED} ready${NC}"
    else
        echo -e "${RED}✗ Webapp: ${READY}/${DESIRED} ready${NC}"
        ALL_HEALTHY=false
    fi
fi

# Check WebSockets
if kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" &>/dev/null; then
    READY=$(kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${WEBMODELER_WEBSOCKETS}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    if [[ "${READY}" == "${DESIRED}" ]] && [[ "${READY}" != "0" ]]; then
        echo -e "${GREEN}✓ WebSockets: ${READY}/${DESIRED} ready${NC}"
    else
        echo -e "${RED}✗ WebSockets: ${READY}/${DESIRED} ready${NC}"
        ALL_HEALTHY=false
    fi
fi

# Validate CNPG if used
if [[ "${TARGET_DB_TYPE:-}" == "cnpg" ]]; then
    echo ""
    echo -e "${BLUE}=== Validating CNPG Cluster ===${NC}"
    echo ""

    CNPG_STATUS=$(kubectl get cluster "${CNPG_CLUSTER_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [[ "$CNPG_STATUS" == "Cluster in healthy state" ]]; then
        echo -e "${GREEN}✓ CNPG Cluster: Healthy${NC}"
    else
        echo -e "${RED}✗ CNPG Cluster: ${CNPG_STATUS}${NC}"
        ALL_HEALTHY=false
    fi
fi

echo ""
echo -e "${BLUE}=== Validating Database Connectivity ===${NC}"
echo ""

# Test database connection
kubectl run webmodeler-db-test-${RANDOM} \
    --image=postgres:15 \
    --restart=Never \
    --rm -i \
    --namespace="${NAMESPACE}" \
    --env="PGPASSWORD=$(kubectl get secret "${DB_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)" \
    -- psql -h "${TARGET_PG_HOST}" -p "${TARGET_PG_PORT:-5432}" -U "${TARGET_PG_USER:-webmodeler}" -d "${TARGET_PG_DATABASE:-web-modeler}" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null && \
    echo -e "${GREEN}✓ Database connectivity: OK${NC}" || \
    echo -e "${YELLOW}⚠ Database connectivity: Could not verify${NC}"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================================================="
if [[ "${ALL_HEALTHY}" == "true" ]]; then
    echo -e "${GREEN}  Migration Validated Successfully!${NC}"
else
    echo -e "${YELLOW}  Migration Complete with Warnings${NC}"
fi
echo "============================================================================="
echo ""

# =============================================================================
# Cleanup Commands
# =============================================================================
echo -e "${BLUE}=== Bitnami Cleanup Commands ===${NC}"
echo ""
echo -e "${YELLOW}The following commands will remove Bitnami PostgreSQL resources.${NC}"
echo -e "${YELLOW}Run these ONLY after 24-48 hours of successful validation.${NC}"
echo ""
echo "# ============================================================================="
echo "# DELETE BITNAMI WEBMODELER POSTGRESQL DATA - THIS IS IRREVERSIBLE!"
echo "# ============================================================================="
echo ""

echo "# Delete Bitnami PostgreSQL StatefulSet"
echo "echo \"Deleting PostgreSQL StatefulSet ${PG_STS_NAME}...\""
echo "kubectl delete statefulset ${PG_STS_NAME} -n ${NAMESPACE} --cascade=orphan"
echo ""

echo "# Delete PostgreSQL pods"
echo "echo \"Deleting PostgreSQL pods...\""
echo "kubectl delete pods -l app.kubernetes.io/name=postgresql,app.kubernetes.io/component=web-modeler -n ${NAMESPACE}"
echo ""

echo "# Delete PostgreSQL services"
echo "echo \"Deleting PostgreSQL services...\""
echo "kubectl delete service ${PG_STS_NAME} -n ${NAMESPACE} --ignore-not-found"
echo "kubectl delete service ${PG_STS_NAME}-headless -n ${NAMESPACE} --ignore-not-found"
echo ""

echo "# Delete PostgreSQL PVCs (DATA LOSS!)"
echo "echo \"WARNING: This will delete all Bitnami PostgreSQL data!\""
echo "echo \"Press Ctrl+C within 10 seconds to cancel...\""
echo "sleep 10"
echo "kubectl delete pvc -l app.kubernetes.io/name=postgresql,app.kubernetes.io/component=web-modeler -n ${NAMESPACE}"
echo ""

echo "# Delete PostgreSQL secrets"
echo "echo \"Deleting PostgreSQL secrets...\""
echo "kubectl delete secret ${PG_STS_NAME} -n ${NAMESPACE} --ignore-not-found"
echo ""

echo "# ============================================================================="
echo "# CLEANUP MIGRATION RESOURCES"
echo "# ============================================================================="
echo ""

echo "# Delete backup jobs"
echo "kubectl delete jobs -l app=webmodeler-migration -n ${NAMESPACE}"
echo ""

echo "# Clean up state directory"
echo "# rm -rf ${MIGRATION_STATE_DIR}"
echo ""

echo "============================================================================="
echo ""
echo -e "${GREEN}Migration complete!${NC}"
echo ""

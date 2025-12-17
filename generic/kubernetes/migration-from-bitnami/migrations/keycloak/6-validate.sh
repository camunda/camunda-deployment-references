#!/bin/bash
# =============================================================================
# Keycloak Migration - Step 6: Validate and Show Cleanup Commands
# =============================================================================
# This script validates the migration and shows commands to clean up
# Bitnami resources (as echo only - user decides when to run them).
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
echo "  Keycloak Migration - Step 6: Validate and Cleanup"
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

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

# =============================================================================
# Validation
# =============================================================================
ALL_HEALTHY=true

echo -e "${BLUE}=== Validating Keycloak Operator ===${NC}"
echo ""

# Check Keycloak Operator instance status
KC_STATUS=$(kubectl get keycloak "${KEYCLOAK_INSTANCE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [[ "$KC_STATUS" == "True" ]]; then
    echo -e "${GREEN}✓ Keycloak Operator instance: Ready${NC}"
else
    echo -e "${RED}✗ Keycloak Operator instance: ${KC_STATUS}${NC}"
    ALL_HEALTHY=false
fi

# Check Keycloak pods
KC_PODS=$(kubectl get pods -l "app=keycloak" -n "${NAMESPACE}" -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
if echo "$KC_PODS" | grep -q "Running"; then
    echo -e "${GREEN}✓ Keycloak pods: Running${NC}"
else
    echo -e "${RED}✗ Keycloak pods: ${KC_PODS:-NotFound}${NC}"
    ALL_HEALTHY=false
fi

echo ""
echo -e "${BLUE}=== Validating Keycloak Connectivity ===${NC}"
echo ""

KC_SERVICE="${KEYCLOAK_INSTANCE_NAME}-service"
KC_HOST="${KC_SERVICE}.${NAMESPACE}.svc.cluster.local"

# Test Keycloak health endpoint
kubectl run kc-health-check-${RANDOM} \
    --image=curlimages/curl:latest \
    --restart=Never \
    --rm -i \
    --namespace="${NAMESPACE}" \
    -- curl -sf "http://${KC_HOST}:80/auth/health/ready" 2>/dev/null && \
    echo -e "${GREEN}✓ Keycloak health check: OK${NC}" || \
    echo -e "${YELLOW}⚠ Keycloak health check: Could not verify (may still be starting)${NC}"

echo ""
echo -e "${BLUE}=== Validating Identity ===${NC}"
echo ""

IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"

if kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
    READY=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    if [[ "${READY}" == "${DESIRED}" ]] && [[ "${READY}" != "0" ]]; then
        echo -e "${GREEN}✓ Identity: ${READY}/${DESIRED} ready${NC}"
    else
        echo -e "${RED}✗ Identity: ${READY}/${DESIRED} ready${NC}"
        ALL_HEALTHY=false
    fi
else
    echo -e "${YELLOW}⚠ Identity deployment not found (may not be enabled)${NC}"
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

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================================================="
if [[ "${ALL_HEALTHY}" == "true" ]]; then
    echo -e "${GREEN}  Migration Validated Successfully!${NC}"
else
    echo -e "${YELLOW}  Migration Complete with Warnings${NC}"
    echo ""
    echo "Some components may still be starting. Check status with:"
    echo "  kubectl get keycloak -n ${NAMESPACE}"
    echo "  kubectl get pods -n ${NAMESPACE}"
fi
echo "============================================================================="
echo ""

# =============================================================================
# Cleanup Commands (Echo Only)
# =============================================================================
echo -e "${BLUE}=== Bitnami Cleanup Commands ===${NC}"
echo ""
echo -e "${YELLOW}The following commands will remove Bitnami Keycloak resources.${NC}"
echo -e "${YELLOW}Run these ONLY after you have verified the migration is successful${NC}"
echo -e "${YELLOW}and you are confident you no longer need the Bitnami installation.${NC}"
echo ""
echo "# Wait 24-48 hours before running these commands"
echo ""
echo "# ============================================================================="
echo "# DELETE BITNAMI KEYCLOAK DATA - THIS IS IRREVERSIBLE!"
echo "# ============================================================================="
echo ""

# Keycloak StatefulSet
echo "# Delete Bitnami Keycloak StatefulSet"
echo "echo \"Deleting Keycloak StatefulSet ${KC_STS_NAME}...\""
echo "kubectl delete statefulset ${KC_STS_NAME} -n ${NAMESPACE} --cascade=orphan"
echo ""

# Keycloak Pods
echo "# Delete any orphaned Keycloak pods"
echo "echo \"Deleting orphaned Keycloak pods...\""
echo "kubectl delete pods -l app.kubernetes.io/name=keycloak,app.kubernetes.io/instance=${RELEASE_NAME} -n ${NAMESPACE}"
echo ""

# Keycloak Services
echo "# Delete Bitnami Keycloak services"
echo "echo \"Deleting Keycloak services...\""
echo "kubectl delete service ${RELEASE_NAME}-keycloak -n ${NAMESPACE} --ignore-not-found"
echo "kubectl delete service ${RELEASE_NAME}-keycloak-headless -n ${NAMESPACE} --ignore-not-found"
echo ""

# Keycloak PVCs
echo "# Delete Bitnami Keycloak PVCs (if any)"
echo "echo \"Deleting Keycloak PVCs...\""
echo "kubectl delete pvc -l app.kubernetes.io/name=keycloak,app.kubernetes.io/instance=${RELEASE_NAME} -n ${NAMESPACE}"
echo ""

# Keycloak Secrets
echo "# Delete Bitnami Keycloak secrets"
echo "echo \"Deleting Keycloak secrets...\""
echo "kubectl delete secret ${RELEASE_NAME}-keycloak -n ${NAMESPACE} --ignore-not-found"
echo ""

# PostgreSQL (if integrated)
if [[ "$PG_MODE" == "integrated" ]]; then
    echo "# ============================================================================="
    echo "# DELETE BITNAMI POSTGRESQL DATA - THIS IS IRREVERSIBLE!"
    echo "# ============================================================================="
    echo ""

    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/postgres.env" 2>/dev/null || true

    echo "# Delete Bitnami Keycloak PostgreSQL StatefulSet"
    echo "echo \"Deleting PostgreSQL StatefulSet ${PG_STS_NAME:-${RELEASE_NAME}-keycloak-postgresql}...\""
    echo "kubectl delete statefulset ${PG_STS_NAME:-${RELEASE_NAME}-keycloak-postgresql} -n ${NAMESPACE} --cascade=orphan"
    echo ""

    echo "# Delete PostgreSQL pods"
    echo "echo \"Deleting PostgreSQL pods...\""
    echo "kubectl delete pods -l app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${RELEASE_NAME}-keycloak -n ${NAMESPACE}"
    echo ""

    echo "# Delete PostgreSQL services"
    echo "echo \"Deleting PostgreSQL services...\""
    echo "kubectl delete service ${RELEASE_NAME}-keycloak-postgresql -n ${NAMESPACE} --ignore-not-found"
    echo "kubectl delete service ${RELEASE_NAME}-keycloak-postgresql-headless -n ${NAMESPACE} --ignore-not-found"
    echo ""

    echo "# Delete PostgreSQL PVCs (DATA LOSS!)"
    echo "echo \"WARNING: This will delete all Bitnami PostgreSQL data!\""
    echo "echo \"Press Ctrl+C within 10 seconds to cancel...\""
    echo "sleep 10"
    echo "kubectl delete pvc -l app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${RELEASE_NAME}-keycloak -n ${NAMESPACE}"
    echo ""

    echo "# Delete PostgreSQL secrets"
    echo "echo \"Deleting PostgreSQL secrets...\""
    echo "kubectl delete secret ${RELEASE_NAME}-keycloak-postgresql -n ${NAMESPACE} --ignore-not-found"
    echo ""
fi

echo "# ============================================================================="
echo "# CLEANUP MIGRATION RESOURCES"
echo "# ============================================================================="
echo ""

echo "# Delete backup jobs"
echo "kubectl delete jobs -l app=keycloak-migration -n ${NAMESPACE} --ignore-not-found"
echo ""

echo "# Delete backup PVC (optional - may want to keep for safety)"
echo "# kubectl delete pvc ${BACKUP_PVC_NAME:-migration-backup-pvc} -n ${NAMESPACE}"
echo ""

echo "# Clean up state directory"
echo "# rm -rf ${MIGRATION_STATE_DIR}"
echo ""

echo "============================================================================="
echo ""
echo -e "${GREEN}Migration complete!${NC}"
echo ""
echo "Keycloak is now managed by the Keycloak Operator."
if [[ "${TARGET_DB_TYPE:-}" == "cnpg" ]]; then
    echo "PostgreSQL is now managed by CloudNativePG."
elif [[ "${TARGET_DB_TYPE:-}" == "managed" ]]; then
    echo "PostgreSQL is using the managed service at ${TARGET_PG_HOST:-external}."
fi
echo ""

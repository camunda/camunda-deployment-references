#!/bin/bash
# =============================================================================
# Keycloak Migration - Rollback
# =============================================================================
# This script rolls back the Keycloak migration to Bitnami.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION_STATE_DIR="${SCRIPT_DIR}/.state"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================================="
echo "  Keycloak Migration - Rollback"
echo "============================================================================="
echo ""

# Check for skip
if [[ -f "${MIGRATION_STATE_DIR}/skip" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/skip"
    echo -e "${YELLOW}Migration was skipped (${SKIP_REASON}) - nothing to rollback${NC}"
    exit 0
fi

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

echo -e "${YELLOW}⚠ WARNING: This will rollback to Bitnami Keycloak${NC}"
echo ""
echo "This rollback will:"
echo "  1. Restore original Helm values (re-enable Bitnami Keycloak)"
echo "  2. Scale up Keycloak and Identity to original replicas"
echo "  3. Delete Keycloak Operator instance (optional)"
echo "  4. Delete CNPG cluster (if deployed, optional)"
echo ""
read -r -p "Continue with rollback? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""

# Load state if available
if [[ -f "${MIGRATION_STATE_DIR}/keycloak.env" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/keycloak.env"
fi

# =============================================================================
# Step 1: Restore Helm Values
# =============================================================================
echo -e "${BLUE}=== Restoring Helm Values ===${NC}"
echo ""

if [[ -f "${MIGRATION_STATE_DIR}/helm-values-backup.yaml" ]]; then
    echo "Restoring from backup values..."

    helm upgrade "${RELEASE_NAME}" camunda/camunda-platform \
        --namespace "${NAMESPACE}" \
        --values "${MIGRATION_STATE_DIR}/helm-values-backup.yaml" \
        --wait \
        --timeout 10m

    echo -e "${GREEN}✓ Helm release restored${NC}"
else
    echo -e "${YELLOW}No backup values found. Re-enabling Bitnami Keycloak...${NC}"

    helm upgrade "${RELEASE_NAME}" camunda/camunda-platform \
        --namespace "${NAMESPACE}" \
        --reuse-values \
        --set keycloak.enabled=true \
        --wait \
        --timeout 10m

    echo -e "${GREEN}✓ Bitnami Keycloak re-enabled${NC}"
fi

echo ""

# =============================================================================
# Step 2: Restore Replica Counts
# =============================================================================
echo -e "${BLUE}=== Restoring Replica Counts ===${NC}"
echo ""

if [[ -f "${MIGRATION_STATE_DIR}/replica-counts.env" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/replica-counts.env"

    # Restore Keycloak replicas
    if [[ -n "${KC_SAVED_REPLICAS:-}" ]] && [[ "${KC_SAVED_REPLICAS}" != "0" ]]; then
        if kubectl get statefulset "${KC_STS_NAME:-${RELEASE_NAME}-keycloak}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl scale statefulset "${KC_STS_NAME:-${RELEASE_NAME}-keycloak}" \
                -n "${NAMESPACE}" --replicas="${KC_SAVED_REPLICAS}"
            echo -e "${GREEN}✓ Scaled Keycloak to ${KC_SAVED_REPLICAS} replicas${NC}"
        fi
    fi

    # Restore Identity replicas
    IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"
    if [[ -n "${IDENTITY_SAVED_REPLICAS:-}" ]] && [[ "${IDENTITY_SAVED_REPLICAS}" != "0" ]]; then
        if kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl scale deployment "${IDENTITY_DEPLOYMENT}" \
                -n "${NAMESPACE}" --replicas="${IDENTITY_SAVED_REPLICAS}"
            echo -e "${GREEN}✓ Scaled Identity to ${IDENTITY_SAVED_REPLICAS} replicas${NC}"
        fi
    fi
else
    echo -e "${YELLOW}No replica counts backup found. Components will use Helm defaults.${NC}"
fi

echo ""

# =============================================================================
# Step 3: Wait for Components
# =============================================================================
echo -e "${BLUE}=== Waiting for Components ===${NC}"
echo ""

# Wait for Keycloak
KC_STS="${KC_STS_NAME:-${RELEASE_NAME}-keycloak}"
if kubectl get statefulset "${KC_STS}" -n "${NAMESPACE}" &>/dev/null; then
    echo "Waiting for Keycloak..."
    kubectl rollout status statefulset "${KC_STS}" -n "${NAMESPACE}" --timeout=300s || true
fi

# Wait for Identity
IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"
if kubectl get deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
    echo "Waiting for Identity..."
    kubectl rollout status deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || true
fi

echo ""

# =============================================================================
# Step 4: Optional Cleanup of Operator Resources
# =============================================================================
echo -e "${BLUE}=== Cleanup Operator Resources ===${NC}"
echo ""

echo "Do you want to delete the Keycloak Operator instance?"
read -r -p "Delete Keycloak Operator instance? (yes/no): " delete_kc
if [[ "$delete_kc" == "yes" ]]; then
    kubectl delete keycloak "${KEYCLOAK_INSTANCE_NAME:-keycloak}" -n "${NAMESPACE}" --ignore-not-found
    echo -e "${GREEN}✓ Keycloak Operator instance deleted${NC}"
fi

if [[ "${TARGET_DB_TYPE:-}" == "cnpg" ]]; then
    echo ""
    echo "Do you want to delete the CNPG cluster?"
    echo -e "${YELLOW}WARNING: This will delete all data in the CNPG cluster!${NC}"
    read -r -p "Delete CNPG cluster? (yes/no): " delete_cnpg
    if [[ "$delete_cnpg" == "yes" ]]; then
        kubectl delete cluster "${CNPG_CLUSTER_NAME:-pg-keycloak}" -n "${NAMESPACE}" --ignore-not-found
        kubectl delete secret "${CNPG_CLUSTER_NAME:-pg-keycloak}-app-credentials" -n "${NAMESPACE}" --ignore-not-found
        echo -e "${GREEN}✓ CNPG cluster deleted${NC}"
    fi
fi

echo ""
echo "============================================================================="
echo -e "${GREEN}  Rollback Complete!${NC}"
echo "============================================================================="
echo ""
echo "Camunda is now using Bitnami Keycloak again."
echo ""
echo "Verify with:"
echo "  kubectl get statefulset ${KC_STS:-${RELEASE_NAME}-keycloak} -n ${NAMESPACE}"
echo "  kubectl get pods -l app.kubernetes.io/name=keycloak -n ${NAMESPACE}"
echo ""

#!/bin/bash
# =============================================================================
# Identity Migration - Rollback
# =============================================================================
# This script rolls back the Identity PostgreSQL migration to Bitnami.
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
echo "  Identity Migration - Rollback"
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

echo -e "${YELLOW}⚠ WARNING: This will rollback to Bitnami PostgreSQL${NC}"
echo ""
read -r -p "Continue with rollback? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""

# Load state if available
if [[ -f "${MIGRATION_STATE_DIR}/identity.env" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/identity.env"
fi

# =============================================================================
# Restore Helm Values
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
    echo -e "${YELLOW}No backup values found. Re-enabling Bitnami PostgreSQL...${NC}"

    helm upgrade "${RELEASE_NAME}" camunda/camunda-platform \
        --namespace "${NAMESPACE}" \
        --reuse-values \
        --set postgresql.enabled=true \
        --wait \
        --timeout 10m
fi

echo ""

# =============================================================================
# Restore Replica Counts
# =============================================================================
echo -e "${BLUE}=== Restoring Identity ===${NC}"
echo ""

IDENTITY_DEPLOYMENT="${RELEASE_NAME}-identity"

if [[ -f "${MIGRATION_STATE_DIR}/replica-counts.env" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/replica-counts.env"

    if [[ -n "${IDENTITY_SAVED_REPLICAS:-}" ]] && [[ "${IDENTITY_SAVED_REPLICAS}" != "0" ]]; then
        kubectl scale deployment "${IDENTITY_DEPLOYMENT}" \
            -n "${NAMESPACE}" --replicas="${IDENTITY_SAVED_REPLICAS}"
        echo -e "${GREEN}✓ Scaled Identity to ${IDENTITY_SAVED_REPLICAS} replicas${NC}"
    fi
fi

echo "Waiting for Identity..."
kubectl rollout status deployment "${IDENTITY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || true

echo ""

# =============================================================================
# Optional Cleanup
# =============================================================================
echo -e "${BLUE}=== Cleanup Operator Resources ===${NC}"
echo ""

if [[ "${TARGET_DB_TYPE:-}" == "cnpg" ]]; then
    echo "Do you want to delete the CNPG cluster?"
    echo -e "${YELLOW}WARNING: This will delete all data in the CNPG cluster!${NC}"
    read -r -p "Delete CNPG cluster? (yes/no): " delete_cnpg
    if [[ "$delete_cnpg" == "yes" ]]; then
        kubectl delete cluster "${CNPG_CLUSTER_NAME:-pg-identity}" -n "${NAMESPACE}" --ignore-not-found
        kubectl delete secret "${CNPG_CLUSTER_NAME:-pg-identity}-app-credentials" -n "${NAMESPACE}" --ignore-not-found
        echo -e "${GREEN}✓ CNPG cluster deleted${NC}"
    fi
fi

echo ""
echo "============================================================================="
echo -e "${GREEN}  Rollback Complete!${NC}"
echo "============================================================================="
echo ""
echo "Identity is now using Bitnami PostgreSQL again."
echo ""

#!/bin/bash
# =============================================================================
# WebModeler Migration - Rollback
# =============================================================================
# This script rolls back the WebModeler PostgreSQL migration to Bitnami.
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
echo "  WebModeler Migration - Rollback"
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
if [[ -f "${MIGRATION_STATE_DIR}/webmodeler.env" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/webmodeler.env"
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
        --set webModelerPostgresql.enabled=true \
        --wait \
        --timeout 10m
fi

echo ""

# =============================================================================
# Restore Replica Counts
# =============================================================================
echo -e "${BLUE}=== Restoring WebModeler Components ===${NC}"
echo ""

if [[ -f "${MIGRATION_STATE_DIR}/replica-counts.env" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/replica-counts.env"

    # Restore RestAPI
    if [[ -n "${RESTAPI_SAVED_REPLICAS:-}" ]] && [[ "${RESTAPI_SAVED_REPLICAS}" != "0" ]]; then
        if kubectl get deployment "${WEBMODELER_RESTAPI:-${RELEASE_NAME}-web-modeler-restapi}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl scale deployment "${WEBMODELER_RESTAPI:-${RELEASE_NAME}-web-modeler-restapi}" \
                -n "${NAMESPACE}" --replicas="${RESTAPI_SAVED_REPLICAS}"
            echo -e "${GREEN}✓ Scaled RestAPI to ${RESTAPI_SAVED_REPLICAS} replicas${NC}"
        fi
    fi

    # Restore Webapp
    if [[ -n "${WEBAPP_SAVED_REPLICAS:-}" ]] && [[ "${WEBAPP_SAVED_REPLICAS}" != "0" ]]; then
        if kubectl get deployment "${WEBMODELER_WEBAPP:-${RELEASE_NAME}-web-modeler-webapp}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl scale deployment "${WEBMODELER_WEBAPP:-${RELEASE_NAME}-web-modeler-webapp}" \
                -n "${NAMESPACE}" --replicas="${WEBAPP_SAVED_REPLICAS}"
            echo -e "${GREEN}✓ Scaled Webapp to ${WEBAPP_SAVED_REPLICAS} replicas${NC}"
        fi
    fi

    # Restore WebSockets
    if [[ -n "${WEBSOCKETS_SAVED_REPLICAS:-}" ]] && [[ "${WEBSOCKETS_SAVED_REPLICAS}" != "0" ]]; then
        if kubectl get deployment "${WEBMODELER_WEBSOCKETS:-${RELEASE_NAME}-web-modeler-websockets}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl scale deployment "${WEBMODELER_WEBSOCKETS:-${RELEASE_NAME}-web-modeler-websockets}" \
                -n "${NAMESPACE}" --replicas="${WEBSOCKETS_SAVED_REPLICAS}"
            echo -e "${GREEN}✓ Scaled WebSockets to ${WEBSOCKETS_SAVED_REPLICAS} replicas${NC}"
        fi
    fi
fi

echo ""
echo "Waiting for WebModeler components..."

# Wait for RestAPI
if kubectl get deployment "${WEBMODELER_RESTAPI:-${RELEASE_NAME}-web-modeler-restapi}" -n "${NAMESPACE}" &>/dev/null; then
    kubectl rollout status deployment "${WEBMODELER_RESTAPI:-${RELEASE_NAME}-web-modeler-restapi}" -n "${NAMESPACE}" --timeout=300s || true
fi

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
        kubectl delete cluster "${CNPG_CLUSTER_NAME:-pg-webmodeler}" -n "${NAMESPACE}" --ignore-not-found
        kubectl delete secret "${CNPG_CLUSTER_NAME:-pg-webmodeler}-app-credentials" -n "${NAMESPACE}" --ignore-not-found
        echo -e "${GREEN}✓ CNPG cluster deleted${NC}"
    fi
fi

echo ""
echo "============================================================================="
echo -e "${GREEN}  Rollback Complete!${NC}"
echo "============================================================================="
echo ""
echo "WebModeler is now using Bitnami PostgreSQL again."
echo ""

#!/bin/bash
# =============================================================================
# Orchestration Migration - Rollback
# =============================================================================
# This script rolls back the Elasticsearch migration to Bitnami.
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
echo "  Orchestration Migration - Rollback"
echo "============================================================================="
echo ""

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo ""

echo -e "${YELLOW}⚠ WARNING: This will rollback to Bitnami Elasticsearch${NC}"
echo ""
read -r -p "Continue with rollback? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""
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
    echo -e "${YELLOW}No backup values found. Enabling Bitnami Elasticsearch...${NC}"

    helm upgrade "${RELEASE_NAME}" camunda/camunda-platform \
        --namespace "${NAMESPACE}" \
        --reuse-values \
        --set elasticsearch.enabled=true \
        --wait \
        --timeout 10m
fi

echo ""
echo -e "${BLUE}=== Restoring Replica Counts ===${NC}"
echo ""

if [[ -f "${MIGRATION_STATE_DIR}/replica-counts.env" ]]; then
    # shellcheck source=/dev/null
    source "${MIGRATION_STATE_DIR}/replica-counts.env"

    COMPONENTS=("zeebe" "zeebe-gateway" "operate" "tasklist" "optimize")

    for comp in "${COMPONENTS[@]}"; do
        REPLICAS_VAR="${comp//-/_}"
        REPLICAS="${!REPLICAS_VAR:-1}"
        DEPLOYMENT="${RELEASE_NAME}-${comp}"

        if kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl scale deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --replicas="${REPLICAS}"
            echo -e "${GREEN}✓ Scaled deployment ${comp} to ${REPLICAS}${NC}"
        elif kubectl get statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl scale statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" --replicas="${REPLICAS}"
            echo -e "${GREEN}✓ Scaled statefulset ${comp} to ${REPLICAS}${NC}"
        fi
    done
else
    echo -e "${YELLOW}No replica counts backup found. Components will use Helm defaults.${NC}"
fi

echo ""
echo -e "${BLUE}=== Waiting for Components ===${NC}"
echo ""

COMPONENTS=("zeebe" "zeebe-gateway" "operate" "tasklist" "optimize")

for comp in "${COMPONENTS[@]}"; do
    DEPLOYMENT="${RELEASE_NAME}-${comp}"
    echo "Waiting for ${comp}..."

    if kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl rollout status deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || true
    elif kubectl get statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl rollout status statefulset "${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s || true
    fi
done

echo ""
echo "============================================================================="
echo -e "${GREEN}  Rollback Complete!${NC}"
echo "============================================================================="
echo ""
echo "Camunda is now using Bitnami Elasticsearch again."
echo ""
echo "You can safely delete the ECK cluster if no longer needed:"
echo "  kubectl delete elasticsearch camunda-elasticsearch-eck -n ${NAMESPACE}"
echo ""

#!/bin/bash
# =============================================================================
# Rollback — Restore pre-migration Helm configuration
# =============================================================================
# Reverts the Camunda Helm release to the Bitnami-backed configuration that
# was saved before cutover. Does NOT delete the operator-managed resources
# (CNPG clusters, ECK, Keycloak CR) so you can retry later.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
parse_common_args "$@"
load_state

section "Rollback"

echo "This will:"
echo "  1. Restore the previous Helm values (re-enable Bitnami components)"
echo "  2. Restart Camunda on the old infrastructure"
echo ""
echo "The operator-managed resources (CNPG/ECK/Keycloak) will NOT be deleted."
echo "You can delete them manually after verifying the rollback."
echo ""
confirm "Proceed with rollback?"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Restore Helm
# ─────────────────────────────────────────────────────────────────────────────
section "Restoring Helm Configuration"
helm_rollback_from_backup

# ─────────────────────────────────────────────────────────────────────────────
# 2. Wait for deployments to stabilize
# ─────────────────────────────────────────────────────────────────────────────
section "Waiting for Camunda to restart"

RELEASE="${CAMUNDA_RELEASE_NAME}"
kubectl rollout status deployment -n "${NAMESPACE}" \
    -l "app.kubernetes.io/instance=${RELEASE}" --timeout=600s 2>/dev/null || true

if kubectl get statefulset "${RELEASE}-zeebe" -n "${NAMESPACE}" &>/dev/null; then
    kubectl rollout status statefulset "${RELEASE}-zeebe" -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true
fi

section "Rollback Complete"
echo "Camunda is running on the original Bitnami infrastructure."
echo ""
echo "To clean up operator-managed resources (optional):"
echo "  kubectl delete cluster --all -n ${NAMESPACE}"
echo "  kubectl delete elasticsearch --all -n ${NAMESPACE}"
echo "  kubectl delete keycloak --all -n ${NAMESPACE}"
echo "  kubectl delete pvc ${BACKUP_PVC} -n ${NAMESPACE}"

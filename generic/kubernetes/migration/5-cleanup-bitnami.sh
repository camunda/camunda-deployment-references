#!/bin/bash
# =============================================================================
# Phase 5: Clean Up Old Bitnami Resources (NO DOWNTIME)
# =============================================================================
# After migration and validation, this phase removes leftover Bitnami
# sub-chart resources (StatefulSets, PVCs, Services) that are no longer
# used. Camunda is already running on operator-managed infrastructure at
# this point.
#
# What is removed:
#   - Old Bitnami PostgreSQL StatefulSets and their PVCs
#   - Old Bitnami Elasticsearch StatefulSet and its PVCs
#   - Old Bitnami Keycloak StatefulSet
#   - Migration backup PVC
#
# After cleanup, a re-verification ensures the platform still works
# without the old resources.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Used by lib.sh after sourcing
CURRENT_SCRIPT="5-cleanup-bitnami.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
parse_common_args "$@"
load_state

check_env
require_phase 4 "Phase 4 (validate)"

timer_start

section "Phase 5: Clean Up Old Bitnami Resources"

show_plan 5
run_hooks "pre-phase-5"

RELEASE="${CAMUNDA_RELEASE_NAME}"
DELETED=0

# ─────────────────────────────────────────────────────────────────────────────
# WARNING: Destructive operation
# ─────────────────────────────────────────────────────────────────────────────
echo ""
log_warn "⚠ This phase is DESTRUCTIVE and IRREVERSIBLE."
echo "  Old Bitnami StatefulSets, PVCs, and backup data will be permanently deleted."
echo "  After this, rollback to Bitnami sub-charts is no longer possible."
echo ""
echo "  Before proceeding, ensure you have:"
echo "    1. A full backup of all databases (pg_dumpall or equivalent)"
echo "    2. PVC / volume snapshots stored in cold storage (S3 Glacier, GCS Archive, etc.)"
echo "    3. Verified the application is fully functional on operator-managed backends"
echo ""

# Helper: delete a StatefulSet and its associated PVCs (by label selector).
delete_sts_and_pvcs() {
    local sts_name="$1"

    if ! kubectl get statefulset "$sts_name" -n "${NAMESPACE}" &>/dev/null; then
        log_info "StatefulSet ${sts_name} not found (already removed)"
        return 0
    fi

    log_info "Deleting StatefulSet ${sts_name} ..."
    kubectl delete statefulset "$sts_name" -n "${NAMESPACE}" --wait=true --timeout=60s
    DELETED=$((DELETED + 1))

    # PVCs created by StatefulSet volumeClaimTemplates follow the naming
    # convention: <volumeName>-<sts-name>-<ordinal>
    local pvcs
    pvcs=$(kubectl get pvc -n "${NAMESPACE}" -o name 2>/dev/null \
        | grep -E "(^|/).*${sts_name}-[0-9]+$" || true)

    if [[ -n "$pvcs" ]]; then
        log_info "Deleting PVCs for ${sts_name} ..."
        echo "$pvcs" | xargs kubectl delete -n "${NAMESPACE}" --wait=false
        DELETED=$((DELETED + $(echo "$pvcs" | wc -l)))
    fi
}

# Helper: delete a service if it exists.
delete_service() {
    local svc_name="$1"

    if kubectl get service "$svc_name" -n "${NAMESPACE}" &>/dev/null; then
        log_info "Deleting Service ${svc_name} ..."
        kubectl delete service "$svc_name" -n "${NAMESPACE}" --wait=false
        DELETED=$((DELETED + 1))
    fi
}

confirm "Remove old Bitnami resources? Camunda must be running on operator-managed backends"

# ─────────────────────────────────────────────────────────────────────────────
# 1. PostgreSQL StatefulSets + PVCs
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${MIGRATE_IDENTITY}" == "true" || "${MIGRATE_KEYCLOAK}" == "true" || "${MIGRATE_WEBMODELER}" == "true" ]]; then
    section "Old Bitnami PostgreSQL"

    for component in identity keycloak webmodeler; do
        migrate_var="MIGRATE_${component^^}"
        if [[ "${!migrate_var}" != "true" ]]; then continue; fi

        sts_name=$(detect_pg_sts "$component" 2>/dev/null || true)
        if [[ -n "$sts_name" ]]; then
            delete_sts_and_pvcs "$sts_name"
            # Also remove the headless service (Bitnami creates <sts>-hl)
            delete_service "${sts_name}-hl"
            delete_service "${sts_name}"
        else
            log_info "No Bitnami PG StatefulSet found for ${component} (already removed)"
        fi
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Elasticsearch StatefulSet + PVCs
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
    section "Old Bitnami Elasticsearch"

    # Bitnami ES StatefulSet is typically named <release>-elasticsearch-master
    es_sts=$(kubectl get statefulset -n "${NAMESPACE}" -o name 2>/dev/null \
        | grep -E "elasticsearch" \
        | grep -v "${ECK_CLUSTER_NAME}-es-" \
        | sed 's|statefulset.apps/||' \
        | head -1 || true)

    if [[ -n "$es_sts" ]]; then
        delete_sts_and_pvcs "$es_sts"
        # Bitnami ES ClusterIP service (without -master suffix)
        delete_service "${es_sts%-master}"
        delete_service "${es_sts}"
    else
        log_info "No old Bitnami ES StatefulSet found (already removed)"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Keycloak Bitnami StatefulSet
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    section "Old Bitnami Keycloak"

    kc_sts="${RELEASE}-keycloak"
    if kubectl get statefulset "$kc_sts" -n "${NAMESPACE}" &>/dev/null; then
        delete_sts_and_pvcs "$kc_sts"
    else
        log_info "No old Bitnami Keycloak StatefulSet found (already removed)"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Migration backup PVC
# ─────────────────────────────────────────────────────────────────────────────
section "Migration Backup PVC"

if kubectl get pvc "${BACKUP_PVC}" -n "${NAMESPACE}" &>/dev/null; then
    log_info "Deleting migration backup PVC ${BACKUP_PVC} ..."
    kubectl delete pvc "${BACKUP_PVC}" -n "${NAMESPACE}" --wait=false
    DELETED=$((DELETED + 1))
else
    log_info "Backup PVC ${BACKUP_PVC} not found (already removed)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Re-verify: ensure Camunda still works without old resources
# ─────────────────────────────────────────────────────────────────────────────
section "Re-verification After Cleanup"
log_info "Waiting for the system to stabilize ..."
sleep 15

ERRORS=0

# Check that all Camunda deployments are still healthy
log_info "Checking Camunda deployments ..."
for comp in "${CAMUNDA_DEPLOYMENTS[@]}"; do
    deploy="${RELEASE}-${comp}"
    if kubectl get deployment "$deploy" -n "${NAMESPACE}" &>/dev/null; then
        if kubectl rollout status deployment "$deploy" -n "${NAMESPACE}" --timeout=60s &>/dev/null; then
            log_success "Deployment ${deploy}: healthy"
        else
            log_error "Deployment ${deploy}: not ready after cleanup"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

# Zeebe StatefulSet
if kubectl get statefulset "${RELEASE}-zeebe" -n "${NAMESPACE}" &>/dev/null; then
    if kubectl rollout status statefulset "${RELEASE}-zeebe" -n "${NAMESPACE}" --timeout=120s &>/dev/null; then
        log_success "StatefulSet ${RELEASE}-zeebe: healthy"
    else
        log_error "StatefulSet ${RELEASE}-zeebe: not ready after cleanup"
        ERRORS=$((ERRORS + 1))
    fi
fi

# WebModeler
for comp in "${CAMUNDA_WEBMODELER_COMPONENTS[@]}"; do
    for prefix in web-modeler webmodeler; do
        deploy="${RELEASE}-${prefix}-${comp}"
        if kubectl get deployment "$deploy" -n "${NAMESPACE}" &>/dev/null; then
            if kubectl rollout status deployment "$deploy" -n "${NAMESPACE}" --timeout=60s &>/dev/null; then
                log_success "Deployment ${deploy}: healthy"
            else
                log_error "Deployment ${deploy}: not ready after cleanup"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done
done

# Operator-managed targets still healthy
if [[ "${MIGRATE_IDENTITY}" == "true" || "${MIGRATE_KEYCLOAK}" == "true" || "${MIGRATE_WEBMODELER}" == "true" ]] && ! is_external_pg; then
    for cluster in "${CNPG_IDENTITY_CLUSTER}" "${CNPG_KEYCLOAK_CLUSTER}" "${CNPG_WEBMODELER_CLUSTER}"; do
        if kubectl get cluster "$cluster" -n "${NAMESPACE}" &>/dev/null; then
            status=$(kubectl get cluster "$cluster" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)
            if [[ "$status" == "Cluster in healthy state" ]]; then
                log_success "CNPG ${cluster}: ${status}"
            else
                log_error "CNPG ${cluster}: ${status}"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done
fi

if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]] && ! is_external_es; then
    es_phase=$(kubectl get elasticsearch "${ECK_CLUSTER_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
    if [[ "$es_phase" == "Ready" ]]; then
        log_success "ECK ${ECK_CLUSTER_NAME}: ${es_phase}"
    else
        log_error "ECK ${ECK_CLUSTER_NAME}: ${es_phase}"
        ERRORS=$((ERRORS + 1))
    fi
fi

if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    kc_ready=$(kubectl get keycloak keycloak -n "${NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [[ "$kc_ready" == "True" ]]; then
        log_success "Keycloak CR: Ready"
    else
        log_error "Keycloak CR: Not ready after cleanup"
        ERRORS=$((ERRORS + 1))
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
section "Cleanup Summary ($(timer_elapsed))"

log_info "Deleted ${DELETED} resource(s)"

if [[ $ERRORS -eq 0 ]]; then
    log_success "Cleanup complete. All re-verification checks passed."
    echo ""
    echo "The migration is fully complete. Old Bitnami resources have been removed"
    echo "and Camunda is running entirely on operator-managed infrastructure."
else
    log_error "${ERRORS} re-verification check(s) failed after cleanup."
    echo ""
    echo "Some components may have depended on old Bitnami resources."
    echo "Review the errors above and check pod logs for details."
fi

run_hooks "post-phase-5"
complete_phase 5

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi

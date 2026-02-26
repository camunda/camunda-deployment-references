#!/bin/bash
# =============================================================================
# Phase 3: Freeze → Final Backup → Restore → Cutover (DOWNTIME WINDOW)
# =============================================================================
# This is the only phase that causes downtime. It:
#   1. Freezes all Camunda components (scale to 0)
#   2. Takes a final consistent backup of all sources
#   3. Restores data to the new operator-managed targets
#   4. Runs helm upgrade to point Camunda to the new backends
#   5. Unfreezes (scale back up) — application resumes on the new infrastructure
#
# The downtime duration depends on data volume (typically 5-30 minutes).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Used by lib.sh after sourcing
CURRENT_SCRIPT="3-cutover.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
parse_common_args "$@"
load_state

check_env
require_phase 2 "Phase 2 (initial backup)"

timer_start

section "Phase 3: Cutover (downtime window)"

show_plan 3
run_hooks "pre-phase-3"

echo "This will:"
echo "  1. Stop all Camunda components"
echo "  2. Take a final consistent backup"
echo "  3. Restore data to the new operator-managed infrastructure"
echo "  4. Switch Helm configuration to use the new backends"
echo "  5. Restart all components"
echo ""
confirm "Start the cutover? This will cause downtime"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
export TIMESTAMP
RELEASE="${CAMUNDA_RELEASE_NAME}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Back up current Helm values (for rollback)
# ─────────────────────────────────────────────────────────────────────────────
section "Step 1/5: Save Helm state"
helm_backup

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Freeze all Camunda components
# ─────────────────────────────────────────────────────────────────────────────
section "Step 2/5: Freeze components"

DEPLOYMENTS_TO_FREEZE=()

# Always freeze Zeebe (exported as StatefulSet)
if kubectl get statefulset "${RELEASE}-zeebe" -n "${NAMESPACE}" &>/dev/null; then
    DEPLOYMENTS_TO_FREEZE+=("sts/${RELEASE}-zeebe")
fi

# Freeze standard deployments
for comp in "${CAMUNDA_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "${RELEASE}-${comp}" -n "${NAMESPACE}" &>/dev/null; then
        DEPLOYMENTS_TO_FREEZE+=("${RELEASE}-${comp}")
    fi
done

# WebModeler deployments
for comp in "${CAMUNDA_WEBMODELER_COMPONENTS[@]}"; do
    if kubectl get deployment "${RELEASE}-web-modeler-${comp}" -n "${NAMESPACE}" &>/dev/null; then
        DEPLOYMENTS_TO_FREEZE+=("${RELEASE}-web-modeler-${comp}")
    elif kubectl get deployment "${RELEASE}-webmodeler-${comp}" -n "${NAMESPACE}" &>/dev/null; then
        DEPLOYMENTS_TO_FREEZE+=("${RELEASE}-webmodeler-${comp}")
    fi
done

# Keycloak (Bitnami, statefulset)
if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    if kubectl get statefulset "${RELEASE}-keycloak" -n "${NAMESPACE}" &>/dev/null; then
        DEPLOYMENTS_TO_FREEZE+=("sts/${RELEASE}-keycloak")
    fi
fi

if [[ ${#DEPLOYMENTS_TO_FREEZE[@]} -gt 0 ]]; then
    freeze_components "${DEPLOYMENTS_TO_FREEZE[@]}"
else
    log_warn "No deployments found to freeze"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Final consistent backups (app is frozen, no writes)
# ─────────────────────────────────────────────────────────────────────────────
section "Step 3/5: Final backups"

do_final_pg_backup() {
    local component="$1"
    local db_name="$2"
    local db_user="$3"
    local sts_var="${component^^}_PG_STS"
    local image_var="${component^^}_PG_IMAGE"
    local sts_name="${!sts_var:-}"
    local pg_image="${!image_var:-${PG_IMAGE:-}}"

    if [[ -z "$pg_image" ]]; then
        log_error "${image_var} (or PG_IMAGE) is not set. Run Phase 2 first to detect the PG image."
        return 1
    fi

    if [[ -z "$sts_name" ]]; then
        sts_name=$(detect_pg_sts "$component" 2>/dev/null) || return 0
    fi

    log_info "Final backup: ${component} (${sts_name})"

    # Introspect to detect PG_SECRET_NAME, PG_SECRET_KEY, PG_IMAGE, etc.
    introspect_pg "${sts_name}"

    export COMPONENT="$component"
    export PG_HOST="${sts_name}.${NAMESPACE}.svc.cluster.local"
    export PG_PORT="5432"
    export PG_DATABASE="$db_name"
    export PG_USERNAME="$db_user"
    export PG_IMAGE="$pg_image"
    # PG_SECRET_NAME and PG_SECRET_KEY are set by introspect_pg above

    # Use "final" as the timestamp for the definitive backup
    local saved_ts="$TIMESTAMP"
    export TIMESTAMP="final"
    backup_pg
    export TIMESTAMP="$saved_ts"

    save_state "${component^^}_FINAL_BACKUP" "${component}-db-final.dump"
}

if [[ "${MIGRATE_IDENTITY}" == "true" ]]; then
    do_final_pg_backup identity "${IDENTITY_DB_NAME}" "${IDENTITY_DB_USER}"
fi

if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    do_final_pg_backup keycloak "${KEYCLOAK_DB_NAME}" "${KEYCLOAK_DB_USER}"
fi

if [[ "${MIGRATE_WEBMODELER}" == "true" ]]; then
    do_final_pg_backup webmodeler "${WEBMODELER_DB_NAME}" "${WEBMODELER_DB_USER}"
fi

if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
    log_info "Final backup: Elasticsearch"
    es_sts="${ES_STS:-}"
    if [[ -z "$es_sts" ]]; then
        es_sts=$(kubectl get statefulset -n "${NAMESPACE}" -o name 2>/dev/null \
            | grep -E "elasticsearch" | head -1 | sed 's|statefulset.apps/||' || echo "")
    fi

    if [[ -n "$es_sts" ]]; then
        export ES_HOST="${es_sts}.${NAMESPACE}.svc.cluster.local"
        export ES_PORT="9200"
        export ES_SECRET_NAME="${RELEASE}-elasticsearch"
        export SNAPSHOT_REPO="migration_backup"
        export SNAPSHOT_NAME="final-${TIMESTAMP}"

        backup_es
        save_state "ES_FINAL_SNAPSHOT" "$SNAPSHOT_NAME"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Restore data to new operator-managed targets
# ─────────────────────────────────────────────────────────────────────────────
section "Step 4/5: Restore to targets"

# Ensure new targets are ready before restoring data.
wait_for_targets_ready

do_pg_restore() {
    local component="$1"
    local db_name="$2"
    local db_user="$3"
    local cluster_name="$4"
    local image_var="${component^^}_PG_IMAGE"

    if is_external_pg; then
        local host_var="EXTERNAL_PG_${component^^}_HOST"
        local port_var="EXTERNAL_PG_${component^^}_PORT"
        local secret_var="EXTERNAL_PG_${component^^}_SECRET"

        log_info "Restoring ${component} → external PG (${!host_var})"

        export COMPONENT="$component"
        export TARGET_PG_HOST="${!host_var}"
        export TARGET_PG_PORT="${!port_var:-5432}"
        export TARGET_PG_DATABASE="$db_name"
        export TARGET_PG_USER="$db_user"
        export DB_SECRET_NAME="${!secret_var}"
    else
        log_info "Restoring ${component} → CNPG ${cluster_name}"

        export COMPONENT="$component"
        export TARGET_PG_HOST="${cluster_name}-rw.${NAMESPACE}.svc.cluster.local"
        export TARGET_PG_PORT="5432"
        export TARGET_PG_DATABASE="$db_name"
        export TARGET_PG_USER="$db_user"
        export DB_SECRET_NAME="${cluster_name}-secret"
    fi

    local pg_img="${!image_var:-${PG_IMAGE:-}}"
    if [[ -z "$pg_img" ]]; then
        log_error "${image_var} (or PG_IMAGE) is not set. Run Phase 2 first to detect the PG image."
        return 1
    fi
    export PG_IMAGE="$pg_img"
    export BACKUP_FILE="${component}-db-final.dump"

    restore_pg
}

if [[ "${MIGRATE_IDENTITY}" == "true" ]]; then
    do_pg_restore identity "${IDENTITY_DB_NAME}" "${IDENTITY_DB_USER}" "${CNPG_IDENTITY_CLUSTER}"
fi

if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    do_pg_restore keycloak "${KEYCLOAK_DB_NAME}" "${KEYCLOAK_DB_USER}" "${CNPG_KEYCLOAK_CLUSTER}"
fi

if [[ "${MIGRATE_WEBMODELER}" == "true" ]]; then
    do_pg_restore webmodeler "${WEBMODELER_DB_NAME}" "${WEBMODELER_DB_USER}" "${CNPG_WEBMODELER_CLUSTER}"
fi

if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
    if is_external_es; then
        log_warn "ES_TARGET_MODE=external — automated ES data migration is not supported"
        log_warn "  Filesystem snapshots require shared storage with the ES process,"
        log_warn "  which is not available for managed services."
        log_warn "  Data transfer options:"
        log_warn "    • elasticdump (npm tool): reads from source, writes to target API"
        log_warn "    • S3 snapshot repo: configure on both source and target ES"
        log_warn "    • Reindex API: requires target whitelist configuration"
        log_warn "    • Fresh start: Camunda rebuilds ES indices from Zeebe on next export"
        log_warn "  Helm will be reconfigured to point to the external ES endpoint."
    else
        log_info "Restoring Elasticsearch → ECK ${ECK_CLUSTER_NAME}"

        export TARGET_ES_HOST="${ECK_CLUSTER_NAME}-es-http.${NAMESPACE}.svc.cluster.local"
        export TARGET_ES_PORT="9200"
        export ES_SECRET_NAME="${ECK_CLUSTER_NAME}-es-elastic-user"
        export SNAPSHOT_REPO="migration_backup"
        export SNAPSHOT_NAME="${ES_FINAL_SNAPSHOT:-final-${TIMESTAMP}}"

        restore_es
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Helm upgrade — switch Camunda to the new backends
# ─────────────────────────────────────────────────────────────────────────────
section "Step 5/5: Helm upgrade"

HELM_VALUES_ARGS=()

# For operator targets, use the operator-based helm values.
# For external targets, skip these (user provides via CUSTOM_HELM_VALUES_FILE).

if [[ "${MIGRATE_IDENTITY}" == "true" ]] && ! is_external_pg; then
    HELM_VALUES_ARGS+=("$(get_helm_values identity)")
fi

if [[ "${MIGRATE_WEBMODELER}" == "true" ]] && ! is_external_pg; then
    HELM_VALUES_ARGS+=("$(get_helm_values webmodeler)")
fi

if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]] && ! is_external_es; then
    HELM_VALUES_ARGS+=("$(get_helm_values elasticsearch)")
fi

if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    # Keycloak always uses the operator — values are always needed
    if [[ -n "${CAMUNDA_DOMAIN:-}" && "${CAMUNDA_DOMAIN}" != "localhost" ]]; then
        HELM_VALUES_ARGS+=("$(get_helm_values keycloak-domain)")
    else
        HELM_VALUES_ARGS+=("$(get_helm_values keycloak-no-domain)")
    fi
fi

# Custom helm values for external service configuration (applied last to override)
if [[ -n "${CUSTOM_HELM_VALUES_FILE:-}" ]]; then
    if [[ ! -f "${CUSTOM_HELM_VALUES_FILE}" ]]; then
        log_error "Custom helm values file not found: ${CUSTOM_HELM_VALUES_FILE}"
        exit 1
    fi
    log_info "Including custom helm values: ${CUSTOM_HELM_VALUES_FILE}"
    HELM_VALUES_ARGS+=("${CUSTOM_HELM_VALUES_FILE}")
fi

if [[ ${#HELM_VALUES_ARGS[@]} -gt 0 ]]; then
    helm_upgrade "${HELM_VALUES_ARGS[@]}"
else
    log_warn "No helm values to apply"
fi

# Components will be restarted by the helm upgrade (replica counts restored
# by the chart defaults). If any were frozen and not covered by helm, restore:
log_info "Waiting for deployments to become ready ..."
sleep 10
kubectl rollout status deployment -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE}" \
    --timeout=600s 2>/dev/null || true

section "Phase 3 Complete — Cutover Done ($(timer_elapsed))"
if is_external_pg || is_external_es; then
    echo "Camunda is now running on the new infrastructure."
    is_external_pg && echo "  PostgreSQL: external managed service"
    is_external_es && echo "  Elasticsearch: external managed service"
    is_external_es && echo "  ⚠  Reminder: ES data must be migrated manually if needed."
else
    echo "Camunda is now running on operator-managed infrastructure."
fi
echo ""
echo "Next: ./4-validate.sh"

run_hooks "post-phase-3"
complete_phase 3

#!/bin/bash
# =============================================================================
# Phase 2: Initial Backup (NO DOWNTIME)
# =============================================================================
# Takes a backup of all data sources while the application is still running.
# This is a "warm" backup — final consistency is ensured in Phase 3 after
# freezing the application.
#
# What it does:
#   1. Introspect source Bitnami StatefulSets (PG + ES)
#   2. Create backup PVC
#   3. Run PG backup jobs for identity, keycloak, webmodeler
#   4. Run ES backup verification for orchestration data
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Used by lib.sh after sourcing
CURRENT_SCRIPT="2-backup.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
parse_common_args "$@"
load_state

check_env
require_phase 1 "Phase 1 (deploy targets)"

timer_start

section "Phase 2: Initial Backup (no downtime)"

show_plan 2
run_hooks "pre-phase-2"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
export TIMESTAMP

ensure_backup_pvc

# ─────────────────────────────────────────────────────────────────────────────
# PostgreSQL backups (one per component)
# ─────────────────────────────────────────────────────────────────────────────

do_pg_backup() {
    local component="$1"
    local db_name="$2"
    local db_user="$3"

    local sts_name
    sts_name=$(detect_pg_sts "$component") || {
        log_warn "${component}: Bitnami PG not found — skipping"
        return 0
    }

    section "  Backup: ${component} PostgreSQL (${sts_name})"
    introspect_pg "$sts_name"

    export COMPONENT="$component"
    export PG_HOST="${sts_name}.${NAMESPACE}.svc.cluster.local"
    export PG_PORT="5432"
    export PG_DATABASE="$db_name"
    export PG_USERNAME="$db_user"
    # PG_SECRET_NAME and PG_SECRET_KEY are auto-detected by introspect_pg

    backup_pg

    # Save state for Phase 3
    save_state "${component^^}_PG_STS" "$sts_name"
    save_state "${component^^}_PG_IMAGE" "$PG_IMAGE"
    save_state "${component^^}_BACKUP_FILE" "${component}-db-${TIMESTAMP}.dump"
    save_state "${component^^}_BACKUP_TIMESTAMP" "$TIMESTAMP"
}

if [[ "${MIGRATE_IDENTITY}" == "true" ]]; then
    do_pg_backup identity "${IDENTITY_DB_NAME}" "${IDENTITY_DB_USER}"
fi

if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    do_pg_backup keycloak "${KEYCLOAK_DB_NAME}" "${KEYCLOAK_DB_USER}"
fi

if [[ "${MIGRATE_WEBMODELER}" == "true" ]]; then
    do_pg_backup webmodeler "${WEBMODELER_DB_NAME}" "${WEBMODELER_DB_USER}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Elasticsearch backup verification
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
    section "  Backup: Elasticsearch"

    introspect_es

    # Use the ClusterIP service name for ES API access (not the StatefulSet name).
    export ES_HOST="${ES_SERVICE}.${NAMESPACE}.svc.cluster.local"
    export ES_PORT="9200"
    export ES_SECRET_NAME="${CAMUNDA_RELEASE_NAME}-elasticsearch"

    backup_es

    save_state "ES_STS" "$ES_STS_NAME"
    save_state "ES_SERVICE" "$ES_SERVICE"
    save_state "ES_IMAGE" "$ES_IMAGE"

    # ── Warm reindex (optional) ──────────────────────────────────────────
    # When ES_WARM_REINDEX=true, perform a full reindex from source to
    # target ES while the application is still running. This pre-populates
    # the target so Phase 3 only needs a fast delta reindex.
    if [[ "${ES_WARM_REINDEX:-false}" == "true" ]]; then
        section "  Warm Reindex: Elasticsearch (no downtime)"
        log_info "Performing warm reindex from source to target ES..."
        log_info "This runs while the app is still active. Phase 3 will only sync the delta."

        # Source ES (Bitnami)
        es_svc="${ES_SERVICE}"
        export SOURCE_ES_HOST="${es_svc}.${NAMESPACE}.svc.cluster.local"
        export SOURCE_ES_PORT="9200"
        export SOURCE_ES_SECRET_NAME="${CAMUNDA_RELEASE_NAME}-elasticsearch"

        if is_external_es; then
            # External target — user must have configured reindex.remote.whitelist
            log_warn "ES_TARGET_MODE=external: ensure the target ES has reindex.remote.whitelist"
            log_warn "  configured to allow pulling data from the source (${SOURCE_ES_HOST}:9200)."
            export TARGET_ES_HOST="${EXTERNAL_ES_HOST}"
            export TARGET_ES_PORT="${EXTERNAL_ES_PORT:-443}"
            export TARGET_ES_SECRET_NAME="${EXTERNAL_ES_SECRET:-external-es}"
        else
            # Operator target (ECK) — whitelist is patched automatically
            export TARGET_ES_HOST="${ECK_CLUSTER_NAME}-es-http.${NAMESPACE}.svc.cluster.local"
            export TARGET_ES_PORT="9200"
            export TARGET_ES_SECRET_NAME="${ECK_CLUSTER_NAME}-es-elastic-user"
        fi

        warm_reindex_es
        save_state "ES_WARM_REINDEX_DONE" "true"
    fi
fi

save_state "PHASE_2_DURATION" "$(timer_elapsed)"
section "Phase 2 Complete ($(timer_elapsed))"
echo "All initial backups are done. The application is still fully operational."
echo ""
echo "IMPORTANT: The next phase (3-cutover.sh) will cause a brief downtime"
echo "while it freezes the application, takes a final consistent backup,"
echo "restores data to the new targets, and switches over."
echo ""
echo "Next: ./3-cutover.sh"

run_hooks "post-phase-2"
complete_phase 2

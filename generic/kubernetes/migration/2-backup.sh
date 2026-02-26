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
#   4. Run ES snapshot backup for orchestration data
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
# Elasticsearch snapshot backup
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
    section "  Backup: Elasticsearch"

    introspect_es

    # The source ES must have path.repo configured for filesystem snapshots.
    # For Bitnami ES, the backup PVC needs to be mounted.
    export ES_HOST="${ES_STS_NAME}.${NAMESPACE}.svc.cluster.local"
    export ES_PORT="9200"
    export ES_SECRET_NAME="${CAMUNDA_RELEASE_NAME}-elasticsearch"
    export SNAPSHOT_REPO="migration_backup"
    export SNAPSHOT_NAME="pre-migration-${TIMESTAMP}"

    backup_es

    save_state "ES_SNAPSHOT_NAME" "$SNAPSHOT_NAME"
    save_state "ES_STS" "$ES_STS_NAME"
    save_state "ES_IMAGE" "$ES_IMAGE"
fi

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

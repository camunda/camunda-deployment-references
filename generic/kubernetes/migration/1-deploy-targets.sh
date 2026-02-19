#!/bin/bash
# =============================================================================
# Phase 1: Deploy target operators and clusters (NO DOWNTIME)
# =============================================================================
# This phase installs the target infrastructure alongside the existing Bitnami
# components. It runs while the application is fully operational.
#
# Delegates to the operator-based reference architecture scripts:
#   ../operator-based/postgresql/deploy.sh  — CNPG operator + PG clusters
#   ../operator-based/elasticsearch/deploy.sh — ECK operator + ES cluster
#   ../operator-based/keycloak/deploy.sh    — Keycloak operator + CR
#
# The Elasticsearch cluster uses a migration-specific manifest that adds
# snapshot repository support (path.repo + backup PVC mount).
#
# Prerequisites:
#   - source env.sh
#   - kubectl configured and pointing to the right cluster
#   - helm repo add camunda https://helm.camunda.io
#   - yq installed (for CNPG CLUSTER_FILTER support)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
parse_common_args "$@"

section "Phase 1: Deploy Target Infrastructure (no downtime)"

if is_external_pg || is_external_es; then
    echo "External target mode is active:"
    is_external_pg && echo "  • PostgreSQL → external managed service (CNPG will NOT be deployed)"
    is_external_es && echo "  • Elasticsearch → external managed service (ECK will NOT be deployed)"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# Customization warning
# ─────────────────────────────────────────────────────────────────────────────
warn_customization

confirm "Have you reviewed and customized the operator-based manifests?"

# ─────────────────────────────────────────────────────────────────────────────
# Resource validation
# ─────────────────────────────────────────────────────────────────────────────
validate_target_resources

# ─────────────────────────────────────────────────────────────────────────────
# 1. PostgreSQL (CNPG) — one cluster per component that needs PG
# ─────────────────────────────────────────────────────────────────────────────

needs_pg_migration() {
    local component="$1"
    detect_pg_sts "$component" >/dev/null 2>&1
}

if [[ "${MIGRATE_IDENTITY}" == "true" ]] || [[ "${MIGRATE_KEYCLOAK}" == "true" ]] || [[ "${MIGRATE_WEBMODELER}" == "true" ]]; then
    section "1/3 — CloudNativePG (operator + clusters)"

    if is_external_pg; then
        log_info "PG_TARGET_MODE=external — CNPG deployment skipped"
        save_state "PG_TARGET_IS_EXTERNAL" "true"
    else
        # Determine which clusters to deploy
        PG_CLUSTERS_TO_DEPLOY=()

        if [[ "${MIGRATE_IDENTITY}" == "true" ]] && needs_pg_migration identity; then
            PG_CLUSTERS_TO_DEPLOY+=("${CNPG_IDENTITY_CLUSTER}")
        fi
        if [[ "${MIGRATE_KEYCLOAK}" == "true" ]] && needs_pg_migration keycloak; then
            PG_CLUSTERS_TO_DEPLOY+=("${CNPG_KEYCLOAK_CLUSTER}")
        fi
        if [[ "${MIGRATE_WEBMODELER}" == "true" ]] && needs_pg_migration webmodeler; then
            PG_CLUSTERS_TO_DEPLOY+=("${CNPG_WEBMODELER_CLUSTER}")
        fi

        if [[ ${#PG_CLUSTERS_TO_DEPLOY[@]} -eq 3 ]]; then
            # All 3 clusters needed — deploy without filter (more efficient)
            deploy_postgresql ""
        elif [[ ${#PG_CLUSTERS_TO_DEPLOY[@]} -gt 0 ]]; then
            # Deploy individual clusters
            for cluster in "${PG_CLUSTERS_TO_DEPLOY[@]}"; do
                deploy_postgresql "$cluster"
            done
        else
            log_info "No PostgreSQL components need migration — skipping CNPG"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Elasticsearch (ECK)
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
    section "2/3 — ECK Elasticsearch"

    if is_external_es; then
        log_info "ES_TARGET_MODE=external — ECK deployment skipped"
        save_state "ES_TARGET_IS_EXTERNAL" "true"
    elif kubectl get elasticsearch "${ECK_CLUSTER_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        log_success "ECK cluster ${ECK_CLUSTER_NAME} already exists — skipping"
    else
        # The ECK cluster manifest mounts the backup PVC for snapshot support,
        # so it must exist before the ES pods can be scheduled.
        ensure_backup_pvc
        deploy_elasticsearch
        save_state "ECK_DEPLOYED" "true"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Keycloak Operator
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    section "3/3 — Keycloak Operator"

    if kubectl get keycloak keycloak -n "${NAMESPACE}" &>/dev/null; then
        log_success "Keycloak CR already exists — skipping"
    else
        deploy_keycloak
        save_state "KEYCLOAK_OPERATOR_DEPLOYED" "true"
    fi
fi

section "Phase 1 Complete"
if is_external_pg || is_external_es; then
    echo "Target infrastructure configured (external targets will be used for data restore)."
else
    echo "All target infrastructure is deployed and running alongside existing Bitnami."
fi
echo "The application is still fully operational — no downtime has occurred."
echo ""
echo "Next: ./2-backup.sh"

#!/bin/bash
# =============================================================================
# Phase 4: Validate (NO DOWNTIME)
# =============================================================================
# Verifies that all Camunda components are healthy after the migration.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Used by lib.sh after sourcing
CURRENT_SCRIPT="4-validate.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
parse_common_args "$@"
load_state

check_env
require_phase 3 "Phase 3 (cutover)"

timer_start

section "Phase 4: Validate Migration"

show_plan 4
run_hooks "pre-phase-4"

RELEASE="${CAMUNDA_RELEASE_NAME}"
ERRORS=0

check() {
    local label="$1"
    shift
    if "$@" &>/dev/null; then
        log_success "$label"
    else
        log_error "$label"
        ERRORS=$((ERRORS + 1))
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Camunda deployments
# ─────────────────────────────────────────────────────────────────────────────
section "Camunda Deployments"

for comp in "${CAMUNDA_DEPLOYMENTS[@]}"; do
    deploy="${RELEASE}-${comp}"
    if kubectl get deployment "$deploy" -n "${NAMESPACE}" &>/dev/null; then
        check "Deployment ${deploy}" \
            kubectl rollout status deployment "$deploy" -n "${NAMESPACE}" --timeout=60s
    fi
done

# Zeebe StatefulSet
if kubectl get statefulset "${RELEASE}-zeebe" -n "${NAMESPACE}" &>/dev/null; then
    check "StatefulSet ${RELEASE}-zeebe" \
        kubectl rollout status statefulset "${RELEASE}-zeebe" -n "${NAMESPACE}" --timeout=120s
fi

# WebModeler
for comp in "${CAMUNDA_WEBMODELER_COMPONENTS[@]}"; do
    for prefix in web-modeler webmodeler; do
        deploy="${RELEASE}-${prefix}-${comp}"
        if kubectl get deployment "$deploy" -n "${NAMESPACE}" &>/dev/null; then
            check "Deployment ${deploy}" \
                kubectl rollout status deployment "$deploy" -n "${NAMESPACE}" --timeout=60s
        fi
    done
done

# ─────────────────────────────────────────────────────────────────────────────
# 2. PostgreSQL targets
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${MIGRATE_IDENTITY}" == "true" || "${MIGRATE_KEYCLOAK}" == "true" || "${MIGRATE_WEBMODELER}" == "true" ]]; then
    if is_external_pg; then
        section "External PostgreSQL Connectivity"

        for pair in "identity:EXTERNAL_PG_IDENTITY" "keycloak:EXTERNAL_PG_KEYCLOAK" "webmodeler:EXTERNAL_PG_WEBMODELER"; do
            comp="${pair%%:*}"
            prefix="${pair##*:}"
            migrate_var="MIGRATE_${comp^^}"
            if [[ "${!migrate_var}" != "true" ]]; then continue; fi

            host_var="${prefix}_HOST"
            port_var="${prefix}_PORT"
            host="${!host_var:-}"
            port="${!port_var:-5432}"

            if [[ -z "$host" ]]; then continue; fi

            # Use the same Bitnami PG image as the source for consistency
            pg_img="${IDENTITY_PG_IMAGE:-${KEYCLOAK_PG_IMAGE:-${WEBMODELER_PG_IMAGE:-${PG_IMAGE:-}}}}"
            if [[ -z "$pg_img" ]]; then
                log_error "No PG image set (IDENTITY_PG_IMAGE, KEYCLOAK_PG_IMAGE, WEBMODELER_PG_IMAGE, or PG_IMAGE). Run Phase 2 first."
                ERRORS=$((ERRORS + 1))
                continue
            fi

            if kubectl run "pg-check-${comp}-${RANDOM}" --rm -i --restart=Never \
                --image="${pg_img}" -n "${NAMESPACE}" -- \
                pg_isready -h "$host" -p "$port" -t 5 &>/dev/null; then
                log_success "External PG ${comp}: reachable (${host}:${port})"
            else
                log_error "External PG ${comp}: unreachable (${host}:${port})"
                ERRORS=$((ERRORS + 1))
            fi
        done
    else
        section "CNPG PostgreSQL Clusters"

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
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Elasticsearch / OpenSearch target
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
    if is_external_es; then
        section "External Elasticsearch Connectivity"

        ES_HOST="${EXTERNAL_ES_HOST:-}"
        ES_PORT="${EXTERNAL_ES_PORT:-443}"

        if [[ -n "$ES_HOST" ]]; then
            # Use the Bitnami ES image from state for connectivity checks
            es_img="${ES_IMAGE:-}"
            if [[ -z "$es_img" ]]; then
                log_error "ES_IMAGE is not set. Run Phase 2 first to detect the ES image."
                ERRORS=$((ERRORS + 1))
            else

            # Try to reach the external ES
            ES_CURL_ARGS=(-sf)
            ES_HAS_CREDS=false
            # Disable xtrace to avoid leaking credentials in logs
            { _xtrace=$(set +o | grep xtrace); set +x; } 2>/dev/null
            es_secret="${EXTERNAL_ES_SECRET:-external-es}"
            if kubectl get secret "${es_secret}" -n "${NAMESPACE}" &>/dev/null; then
                ES_PWD=$(kubectl get secret "${es_secret}" -n "${NAMESPACE}" \
                    -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d || echo "")
                if [[ -n "$ES_PWD" ]]; then
                    ES_CURL_ARGS+=(-u "elastic:${ES_PWD}")
                    ES_HAS_CREDS=true
                fi
            fi

            # When credentials are present, only use HTTPS to avoid leaking
            # the password over plain HTTP or via -k (insecure TLS).
            if [[ "$ES_HAS_CREDS" == "true" ]]; then
                if kubectl run "es-check-ext-${RANDOM}" --rm -i --restart=Never \
                    --image="${es_img}" -n "${NAMESPACE}" -- \
                    curl "${ES_CURL_ARGS[@]}" "https://${ES_HOST}:${ES_PORT}/_cluster/health" &>/dev/null; then
                    eval "$_xtrace" 2>/dev/null
                    log_success "External ES: reachable via HTTPS (${ES_HOST}:${ES_PORT})"
                else
                    eval "$_xtrace" 2>/dev/null
                    log_warn "External ES: could not verify connectivity (${ES_HOST}:${ES_PORT})"
                    log_warn "  This may be expected if auth or network policies restrict access"
                fi
            elif kubectl run "es-check-ext-${RANDOM}" --rm -i --restart=Never \
                --image="${es_img}" -n "${NAMESPACE}" -- \
                curl "${ES_CURL_ARGS[@]}" "http://${ES_HOST}:${ES_PORT}/_cluster/health" &>/dev/null; then
                log_success "External ES: reachable (${ES_HOST}:${ES_PORT})"
            elif kubectl run "es-check-ext-${RANDOM}" --rm -i --restart=Never \
                --image="${es_img}" -n "${NAMESPACE}" -- \
                curl "${ES_CURL_ARGS[@]}" "https://${ES_HOST}:${ES_PORT}/_cluster/health" &>/dev/null; then
                log_success "External ES: reachable via HTTPS (${ES_HOST}:${ES_PORT})"
            else
                log_warn "External ES: could not verify connectivity (${ES_HOST}:${ES_PORT})"
                log_warn "  This may be expected if auth or network policies restrict access"
            fi
            unset ES_PWD
            fi
        fi
    else
        section "ECK Elasticsearch"

        es_phase=$(kubectl get elasticsearch "${ECK_CLUSTER_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        if [[ "$es_phase" == "Ready" ]]; then
            log_success "ECK ${ECK_CLUSTER_NAME}: ${es_phase}"
        else
            log_error "ECK ${ECK_CLUSTER_NAME}: ${es_phase}"
            ERRORS=$((ERRORS + 1))
        fi

        # Quick index check
        # Disable xtrace to avoid leaking credentials in logs
        { _xtrace=$(set +o | grep xtrace); set +x; } 2>/dev/null
        ES_PWD=$(kubectl get secret "${ECK_CLUSTER_NAME}-es-elastic-user" -n "${NAMESPACE}" \
            -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d || echo "")
        if [[ -n "$ES_PWD" ]]; then
            es_img="${ES_IMAGE:-}"
            if [[ -z "$es_img" ]]; then
                eval "$_xtrace" 2>/dev/null
                log_error "ES_IMAGE is not set. Run Phase 2 first to detect the ES image."
                ERRORS=$((ERRORS + 1))
            else
                idx_count=$(kubectl run es-check-${RANDOM} --rm -i --restart=Never \
                    --image="${es_img}" -n "${NAMESPACE}" -- \
                    curl -sf -u "elastic:${ES_PWD}" \
                    "http://${ECK_CLUSTER_NAME}-es-http:9200/_cat/indices" 2>/dev/null | wc -l || echo "0")
                unset ES_PWD
                eval "$_xtrace" 2>/dev/null
                log_info "Elasticsearch indices: ${idx_count}"
            fi
        else
            eval "$_xtrace" 2>/dev/null
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Keycloak Operator
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
    section "Keycloak Operator"

    kc_ready=$(kubectl get keycloak keycloak -n "${NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [[ "$kc_ready" == "True" ]]; then
        log_success "Keycloak CR: Ready"
    else
        log_error "Keycloak CR: Not ready (${kc_ready})"
        ERRORS=$((ERRORS + 1))
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
section "Validation Summary ($(timer_elapsed))"

# Generate migration report regardless of errors.
generate_report

if [[ $ERRORS -eq 0 ]]; then
    log_success "All checks passed! Migration is successful."
    echo ""
    echo "Next: ./5-cleanup-bitnami.sh  (remove old Bitnami resources and re-verify)"
    echo ""
    log_warn "⚠ Phase 5 is DESTRUCTIVE and IRREVERSIBLE."
    echo "  Before running cleanup, strongly consider:"
    echo "    1. Take a full backup of all databases (pg_dumpall)"
    echo "    2. Snapshot PVCs or storage volumes (cloud provider snapshots)"
    echo "    3. Store backups in cold storage (S3 Glacier, GCS Archive, etc.)"
    echo "    4. Keep rollback artifacts in .state/ as a safety net"
    echo ""
    echo "Migration report: ${STATE_DIR}/migration-report.md"
else
    log_error "${ERRORS} check(s) failed. Review the errors above."
    echo ""
    echo "Migration report: ${STATE_DIR}/migration-report.md"
    echo "If needed, rollback with: ./rollback.sh"
fi

run_hooks "post-phase-4"

# Only mark phase 4 complete if all checks passed — phase 5 is destructive
# and must not run after a failed validation.
if [[ $ERRORS -gt 0 ]]; then
    log_error "${ERRORS} validation check(s) failed — phase 4 NOT marked complete."
    exit 1
fi

complete_phase 4

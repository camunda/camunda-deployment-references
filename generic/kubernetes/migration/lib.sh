#!/bin/bash
# =============================================================================
# Migration Library - Shared Functions
# =============================================================================
# Source this file to get access to all migration utilities.
# Usage: source "$(dirname "$0")/lib.sh"
# =============================================================================

set -euo pipefail

# Resolve directories
MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS_DIR="${MIGRATION_DIR}/jobs"
MANIFESTS_DIR="${MIGRATION_DIR}/manifests"
STATE_DIR="${MIGRATION_DIR}/.state"
OPERATOR_BASED_DIR="${MIGRATION_DIR}/../operator-based"

if [[ ! -d "$OPERATOR_BASED_DIR" ]]; then
    echo "ERROR: operator-based/ directory not found at ${OPERATOR_BASED_DIR}" >&2
    echo "The migration scripts require the operator-based reference architecture." >&2
    exit 1
fi

# Normalize the path for cleaner log output
OPERATOR_BASED_DIR="$(cd "$OPERATOR_BASED_DIR" && pwd)"

mkdir -p "${STATE_DIR}"

# =============================================================================
# Logging
# =============================================================================

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_BLUE='\033[0;34m'
_NC='\033[0m'

log_info()    { echo -e "${_BLUE}[INFO]${_NC} $*"; }
log_success() { echo -e "${_GREEN}[OK]${_NC}   $*"; }
log_warn()    { echo -e "${_YELLOW}[WARN]${_NC} $*"; }
log_error()   { echo -e "${_RED}[ERR]${_NC}  $*"; }

section() {
    echo ""
    echo "============================================================================="
    echo "  $*"
    echo "============================================================================="
    echo ""
}

# =============================================================================
# Utilities
# =============================================================================

# Global flag: set to true by parse_common_args when --yes is passed.
AUTO_CONFIRM="false"

# Parse common flags shared by all migration scripts.
# Usage: parse_common_args "$@"   (call at the top of each script)
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y) AUTO_CONFIRM="true" ;;
            *) log_warn "Unknown flag: $1" ;;
        esac
        shift
    done
}

# Ask for interactive confirmation; abort on no.
# Skips the prompt when --yes was passed.
# Usage: confirm "About to delete data"
confirm() {
    local msg="${1:-Continue?}"
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        log_info "${msg} → auto-confirmed (--yes)"
        return 0
    fi
    read -r -p "${msg} (yes/no): " answer
    [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 0; }
}

# Apply an envsubst-templated YAML file and optionally save the rendered result.
# Usage: apply_template <template.yml> [<save-path>]
apply_template() {
    local tpl="$1"
    local save="${2:-}"

    if [[ ! -f "$tpl" ]]; then
        log_error "Template not found: $tpl"
        return 1
    fi

    local rendered
    rendered=$(envsubst < "$tpl")

    if [[ -n "$save" ]]; then
        mkdir -p "$(dirname "$save")"
        echo "$rendered" > "$save"
    fi

    echo "$rendered" | kubectl apply -f -
}

# Run a Kubernetes Job from a template and wait for completion.
# All variables must be exported before calling.
# Usage: run_job <template.yml> <job-name> [timeout_seconds]
run_job() {
    local tpl="$1"
    local job_name="$2"
    local timeout="${3:-1800}"

    log_info "Creating job ${job_name} ..."
    apply_template "$tpl" "${STATE_DIR}/${job_name}.yml"

    log_info "Waiting for job ${job_name} (timeout ${timeout}s) ..."
    if ! kubectl wait --for=condition=complete "job/${job_name}" \
            -n "${NAMESPACE}" --timeout="${timeout}s" 2>/dev/null; then
        log_error "Job ${job_name} failed or timed out"
        kubectl logs -n "${NAMESPACE}" "job/${job_name}" --tail=50 2>/dev/null || true
        return 1
    fi

    log_success "Job ${job_name} completed"
}

# =============================================================================
# Customization Warning
# =============================================================================

warn_customization() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                       ⚠  IMPORTANT: CUSTOMIZATION                      ║"
    echo "╠══════════════════════════════════════════════════════════════════════════╣"
    echo "║  The migration deploys operators and instances using the reference      ║"
    echo "║  architecture from: generic/kubernetes/operator-based/                  ║"
    echo "║                                                                        ║"
    echo "║  It is YOUR responsibility to ensure that:                              ║"
    echo "║  • Cluster manifests match your production requirements                 ║"
    echo "║    (replicas, storage size, resource limits, PG parameters, etc.)       ║"
    echo "║  • Keycloak CR configuration is appropriate for your setup              ║"
    echo "║  • Helm values align with your existing customizations                  ║"
    echo "║                                                                        ║"
    echo "║  Review and customize the files in operator-based/ BEFORE proceeding.   ║"
    echo "║                                                                        ║"
    echo "║  Files to review:                                                      ║"
    echo "║    operator-based/postgresql/postgresql-clusters.yml                    ║"
    echo "║    operator-based/elasticsearch/elasticsearch-cluster.yml              ║"
    echo "║    operator-based/keycloak/keycloak-instance-*.yml                     ║"
    echo "║    operator-based/*/camunda-*-values.yml                               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    if is_external_pg || is_external_es; then
        echo "╔══════════════════════════════════════════════════════════════════════════╗"
        echo "║                  ℹ  EXTERNAL TARGET MODE ACTIVE                        ║"
        echo "╠══════════════════════════════════════════════════════════════════════════╣"
        if is_external_pg; then
        echo "║  PG_TARGET_MODE=external                                               ║"
        echo "║  • CNPG operator will NOT be deployed                                  ║"
        echo "║  • PostgreSQL data will be restored to the external endpoints           ║"
        echo "║  • You must provide CUSTOM_HELM_VALUES_FILE with PG connection info    ║"
        fi
        if is_external_es; then
        echo "║  ES_TARGET_MODE=external                                               ║"
        echo "║  • ECK operator will NOT be deployed                                   ║"
        echo "║  • ES data migration must be done manually (see README)                ║"
        echo "║  • You must provide CUSTOM_HELM_VALUES_FILE with ES connection info    ║"
        fi
        if is_external_pg && [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
        echo "║                                                                        ║"
        echo "║  Keycloak + external PG:                                               ║"
        echo "║  • Keycloak Operator IS still deployed (no managed KC service exists)   ║"
        echo "║  • Set CUSTOM_KEYCLOAK_CONFIG_FILE to a CR pointing to external PG     ║"
        fi
        echo "╚══════════════════════════════════════════════════════════════════════════╝"
        echo ""
    fi
}

# =============================================================================
# Target Mode Helpers
# =============================================================================

is_external_pg() { [[ "${PG_TARGET_MODE:-operator}" == "external" ]]; }
is_external_es() { [[ "${ES_TARGET_MODE:-operator}" == "external" ]]; }

# Validate that external PG configuration is complete for a component.
# Usage: validate_external_pg_config <component>
validate_external_pg_config() {
    local component="$1"
    local comp_upper="${component^^}"
    local host_var="EXTERNAL_PG_${comp_upper}_HOST"
    local port_var="EXTERNAL_PG_${comp_upper}_PORT"
    local secret_var="EXTERNAL_PG_${comp_upper}_SECRET"

    if [[ -z "${!host_var:-}" ]]; then
        log_error "${host_var} must be set when PG_TARGET_MODE=external"
        return 1
    fi

    if ! kubectl get secret "${!secret_var}" -n "${NAMESPACE}" &>/dev/null; then
        log_error "Secret '${!secret_var}' not found in namespace ${NAMESPACE}"
        log_error "  Create it with: kubectl create secret generic ${!secret_var} -n ${NAMESPACE} --from-literal=password=<password>"
        return 1
    fi

    log_success "  ${component}: external PG OK (${!host_var}:${!port_var:-5432})"
    return 0
}

# Validate external ES configuration.
validate_external_es_config() {
    if [[ -z "${EXTERNAL_ES_HOST:-}" ]]; then
        log_error "EXTERNAL_ES_HOST must be set when ES_TARGET_MODE=external"
        return 1
    fi

    if [[ -n "${EXTERNAL_ES_SECRET:-}" ]]; then
        if ! kubectl get secret "${EXTERNAL_ES_SECRET}" -n "${NAMESPACE}" &>/dev/null; then
            log_warn "Secret '${EXTERNAL_ES_SECRET}' not found — assuming no auth or auth configured elsewhere"
        fi
    fi

    # shellcheck disable=SC2153
    log_success "  ES: external config OK (${EXTERNAL_ES_HOST}:${EXTERNAL_ES_PORT})"
    return 0
}

# Validate custom helm values file exists when external targets are used.
validate_custom_helm_values() {
    if (is_external_pg || is_external_es) && [[ -z "${CUSTOM_HELM_VALUES_FILE:-}" ]]; then
        log_error "CUSTOM_HELM_VALUES_FILE must be set when using external targets"
        log_error "  This file should contain helm values to connect Camunda to your managed services"
        return 1
    fi

    if [[ -n "${CUSTOM_HELM_VALUES_FILE:-}" && ! -f "${CUSTOM_HELM_VALUES_FILE}" ]]; then
        log_error "Custom helm values file not found: ${CUSTOM_HELM_VALUES_FILE}"
        return 1
    fi

    return 0
}

# =============================================================================
# Resource Validation
# =============================================================================

# Convert Kubernetes resource quantity to a comparable number (millicores or bytes).
_parse_cpu() {
    local val="$1"
    if [[ "$val" =~ ^([0-9]+)m$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^([0-9]+)$ ]]; then
        echo $(( BASH_REMATCH[1] * 1000 ))
    else
        echo "0"
    fi
}

_parse_memory() {
    local val="$1"
    # Returns value in Mi for comparison
    if [[ "$val" =~ ^([0-9]+)Gi$ ]]; then
        echo $(( BASH_REMATCH[1] * 1024 ))
    elif [[ "$val" =~ ^([0-9]+)Mi$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^([0-9]+)$ ]]; then
        # Pure bytes → convert to Mi
        echo $(( BASH_REMATCH[1] / 1048576 ))
    else
        echo "0"
    fi
}

_parse_storage() {
    # Same as memory — returns value in Gi for comparison
    local val="$1"
    if [[ "$val" =~ ^([0-9]+)Gi$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^([0-9]+)Ti$ ]]; then
        echo $(( BASH_REMATCH[1] * 1024 ))
    elif [[ "$val" =~ ^([0-9]+)Mi$ ]]; then
        echo "0" # Less than 1Gi, effectively 0 for comparison
    else
        echo "0"
    fi
}

# Validate that a target CNPG cluster in postgresql-clusters.yml has adequate resources
# compared to the source Bitnami StatefulSet.
# Usage: validate_pg_resources <component> <cnpg-cluster-name>
validate_pg_resources() {
    local component="$1"
    local cluster_name="$2"
    local issues=0

    local sts_name
    sts_name=$(detect_pg_sts "$component" 2>/dev/null) || return 0

    # Get source storage size
    local source_storage
    source_storage=$(kubectl get statefulset "$sts_name" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}' 2>/dev/null || echo "")

    if [[ -z "$source_storage" ]]; then
        return 0
    fi

    # Get target storage from postgresql-clusters.yml
    local target_storage
    target_storage=$(yq "select(.metadata.name == \"${cluster_name}\") | .spec.storage.size" \
        "${OPERATOR_BASED_DIR}/postgresql/postgresql-clusters.yml" 2>/dev/null || echo "")

    if [[ -n "$target_storage" && -n "$source_storage" ]]; then
        local src_gi tgt_gi
        src_gi=$(_parse_storage "$source_storage")
        tgt_gi=$(_parse_storage "$target_storage")
        if [[ $tgt_gi -lt $src_gi ]]; then
            log_warn "  ${component}: target PG storage (${target_storage}) < source (${source_storage})"
            issues=$((issues + 1))
        else
            log_success "  ${component}: PG storage OK (source=${source_storage}, target=${target_storage})"
        fi
    fi

    return $issues
}

# Validate ECK cluster resources against source ES StatefulSet.
validate_es_resources() {
    local issues=0

    local sts_name
    sts_name=$(kubectl get statefulset -n "${NAMESPACE}" -o name 2>/dev/null \
        | grep -E "elasticsearch" | head -1 | sed 's|statefulset.apps/||' || echo "")

    if [[ -z "$sts_name" ]]; then
        return 0
    fi

    local source_storage source_cpu source_mem
    source_storage=$(kubectl get statefulset "$sts_name" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}' 2>/dev/null || echo "")
    source_cpu=$(kubectl get statefulset "$sts_name" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    source_mem=$(kubectl get statefulset "$sts_name" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")

    # Compare with ECK cluster manifest (migration-specific, has backup PVC)
    local eck_file="${MANIFESTS_DIR}/eck-cluster.yml"
    if [[ -f "$eck_file" ]]; then
        local target_storage target_cpu target_mem
        target_storage=$(grep -A2 'storage:' "$eck_file" | tail -1 | awk '{print $2}' || echo "")
        target_cpu=$(yq '.spec.nodeSets[0].podTemplate.spec.containers[0].resources.requests.cpu' "$eck_file" 2>/dev/null || echo "")
        target_mem=$(yq '.spec.nodeSets[0].podTemplate.spec.containers[0].resources.requests.memory' "$eck_file" 2>/dev/null || echo "")

        if [[ -n "$target_storage" && -n "$source_storage" ]]; then
            local src_gi tgt_gi
            src_gi=$(_parse_storage "$source_storage")
            tgt_gi=$(_parse_storage "$target_storage")
            if [[ $tgt_gi -lt $src_gi ]]; then
                log_warn "  ES: target storage (${target_storage}) < source (${source_storage})"
                issues=$((issues + 1))
            else
                log_success "  ES: storage OK (source=${source_storage}, target=${target_storage})"
            fi
        fi

        if [[ -n "$target_cpu" && -n "$source_cpu" ]]; then
            local src_cpu_m tgt_cpu_m
            src_cpu_m=$(_parse_cpu "$source_cpu")
            tgt_cpu_m=$(_parse_cpu "$target_cpu")
            if [[ $tgt_cpu_m -lt $src_cpu_m ]]; then
                log_warn "  ES: target CPU (${target_cpu}) < source (${source_cpu})"
                issues=$((issues + 1))
            else
                log_success "  ES: CPU OK (source=${source_cpu}, target=${target_cpu})"
            fi
        fi

        if [[ -n "$target_mem" && -n "$source_mem" ]]; then
            local src_mem_mi tgt_mem_mi
            src_mem_mi=$(_parse_memory "$source_mem")
            tgt_mem_mi=$(_parse_memory "$target_mem")
            if [[ $tgt_mem_mi -lt $src_mem_mi ]]; then
                log_warn "  ES: target memory (${target_mem}) < source (${source_mem})"
                issues=$((issues + 1))
            else
                log_success "  ES: memory OK (source=${source_mem}, target=${target_mem})"
            fi
        fi
    fi

    return $issues
}

# =============================================================================
# Version Compatibility Validation
# =============================================================================

# Extract the major version number from a version string.
# Usage: _major_version "17.5" → 17
_major_version() {
    echo "$1" | grep -oE '^[0-9]+' | head -1
}

# Validate PG version compatibility for a component.
# pg_restore can restore dumps from older PG versions to newer ones, NOT the reverse.
# Usage: validate_pg_version <component> <cnpg-cluster-name>
validate_pg_version() {
    local component="$1"
    local cluster_name="$2"
    local issues=0

    local sts_name
    sts_name=$(detect_pg_sts "$component" 2>/dev/null) || return 0

    # Get source PG version from image
    local source_image source_version
    source_image=$(kubectl get statefulset "$sts_name" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
    source_version=$(echo "$source_image" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "")

    if [[ -z "$source_version" ]]; then
        return 0
    fi

    # Get target PG version from CNPG cluster manifest
    local target_image target_version
    target_image=$(yq "select(.metadata.name == \"${cluster_name}\") | .spec.imageName" \
        "${OPERATOR_BASED_DIR}/postgresql/postgresql-clusters.yml" 2>/dev/null || echo "")
    target_version=$(echo "$target_image" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "")

    if [[ -z "$target_version" ]]; then
        return 0
    fi

    local src_major tgt_major
    src_major=$(_major_version "$source_version")
    tgt_major=$(_major_version "$target_version")

    if [[ $tgt_major -lt $src_major ]]; then
        log_error "  ${component}: PG version DOWNGRADE detected (source=${source_version} → target=${target_version})"
        log_error "    pg_restore cannot restore dumps from PG ${src_major} into PG ${tgt_major}"
        issues=1
    elif [[ $tgt_major -gt $src_major ]]; then
        log_warn "  ${component}: PG major version UPGRADE (source=${source_version} → target=${target_version})"
        log_warn "    pg_dump/pg_restore supports this, but test thoroughly in staging first"
    else
        log_success "  ${component}: PG version OK (source=${source_version}, target=${target_version})"
    fi

    return $issues
}

# Validate ES version compatibility.
# ES snapshots can be restored to the same major version or one major version higher.
# e.g., 7.x → 7.x ✓, 7.x → 8.x ✓, 8.x → 7.x ✗, 7.x → 9.x ✗
validate_es_version() {
    local issues=0

    local sts_name
    sts_name=$(kubectl get statefulset -n "${NAMESPACE}" -o name 2>/dev/null \
        | grep -E "elasticsearch" | head -1 | sed 's|statefulset.apps/||' || echo "")

    if [[ -z "$sts_name" ]]; then
        return 0
    fi

    # Get source ES version
    local source_image source_version
    source_image=$(kubectl get statefulset "$sts_name" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
    source_version=$(echo "$source_image" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")

    if [[ -z "$source_version" ]]; then
        return 0
    fi

    # Get target ES version from ECK manifest
    local target_version
    target_version=$(yq '.spec.version' "${MANIFESTS_DIR}/eck-cluster.yml" 2>/dev/null || echo "")

    if [[ -z "$target_version" ]]; then
        return 0
    fi

    local src_major tgt_major
    src_major=$(_major_version "$source_version")
    tgt_major=$(_major_version "$target_version")

    if [[ $tgt_major -lt $src_major ]]; then
        log_error "  ES: version DOWNGRADE detected (source=${source_version} → target=${target_version})"
        log_error "    ES snapshots cannot be restored to an older major version"
        issues=1
    elif [[ $((tgt_major - src_major)) -gt 1 ]]; then
        log_error "  ES: version jump too large (source=${source_version} → target=${target_version})"
        log_error "    ES snapshots can only be restored to the same or +1 major version"
        issues=1
    elif [[ $tgt_major -gt $src_major ]]; then
        log_warn "  ES: major version upgrade (source=${source_version} → target=${target_version})"
        log_warn "    Snapshot restore across major versions is supported but test in staging first"
    else
        log_success "  ES: version OK (source=${source_version}, target=${target_version})"
    fi

    return $issues
}

# Run all resource and version validations.
# Returns the number of warnings found (0 = all good).
validate_target_resources() {
    section "Resource & Version Validation"

    local total_issues=0
    local has_errors=0

    # --- External target configuration checks ---
    if is_external_pg || is_external_es; then
        log_info "External target configuration:"
        if is_external_pg; then
            if [[ "${MIGRATE_IDENTITY}" == "true" ]]; then
                validate_external_pg_config identity || has_errors=1
            fi
            if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
                validate_external_pg_config keycloak || has_errors=1
            fi
            if [[ "${MIGRATE_WEBMODELER}" == "true" ]]; then
                validate_external_pg_config webmodeler || has_errors=1
            fi
        fi
        if is_external_es && [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
            validate_external_es_config || has_errors=1
        fi
        validate_custom_helm_values || has_errors=1
        echo ""
    fi

    # --- Resource checks (only for operator targets, can't introspect managed services) ---
    if ! is_external_pg || ! is_external_es; then
        log_info "Storage, CPU & memory (operator targets):"
        if ! is_external_pg; then
            if [[ "${MIGRATE_IDENTITY}" == "true" ]]; then
                validate_pg_resources identity "${CNPG_IDENTITY_CLUSTER}" || total_issues=$((total_issues + $?))
            fi
            if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
                validate_pg_resources keycloak "${CNPG_KEYCLOAK_CLUSTER}" || total_issues=$((total_issues + $?))
            fi
            if [[ "${MIGRATE_WEBMODELER}" == "true" ]]; then
                validate_pg_resources webmodeler "${CNPG_WEBMODELER_CLUSTER}" || total_issues=$((total_issues + $?))
            fi
        fi
        if ! is_external_es && [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
            validate_es_resources || total_issues=$((total_issues + $?))
        fi
        echo ""
    fi

    # --- Version compatibility checks (only for operator targets) ---
    if ! is_external_pg || ! is_external_es; then
        log_info "Version compatibility (operator targets):"
        if ! is_external_pg; then
            if [[ "${MIGRATE_IDENTITY}" == "true" ]]; then
                validate_pg_version identity "${CNPG_IDENTITY_CLUSTER}" || has_errors=1
            fi
            if [[ "${MIGRATE_KEYCLOAK}" == "true" ]]; then
                validate_pg_version keycloak "${CNPG_KEYCLOAK_CLUSTER}" || has_errors=1
            fi
            if [[ "${MIGRATE_WEBMODELER}" == "true" ]]; then
                validate_pg_version webmodeler "${CNPG_WEBMODELER_CLUSTER}" || has_errors=1
            fi
        fi
        if ! is_external_es && [[ "${MIGRATE_ELASTICSEARCH}" == "true" ]]; then
            validate_es_version || has_errors=1
        fi
        echo ""
    fi

    if [[ $has_errors -gt 0 ]]; then
        log_error "Validation errors detected — fix the issues above before proceeding."
        exit 1
    fi

    if [[ $total_issues -gt 0 ]]; then
        log_warn "${total_issues} resource warning(s) found."
        log_warn "Review the target manifests before proceeding."
        echo ""
        confirm "Continue despite resource warnings?"
    else
        log_success "All checks passed."
    fi
}

# =============================================================================
# Operator & Instance Deployment (delegates to operator-based/ scripts)
# =============================================================================
# These functions call the deploy scripts from generic/kubernetes/operator-based/
# which handle both operator installation and instance deployment.

# Deploy CNPG operator + secrets + PostgreSQL cluster(s).
# Usage: deploy_postgresql [cluster-filter]
#   cluster-filter: optional, e.g. "pg-identity" to deploy only that cluster.
#                   If empty, deploys ALL clusters from postgresql-clusters.yml.
deploy_postgresql() {
    local cluster_filter="${1:-}"

    if is_external_pg; then
        log_info "PG_TARGET_MODE=external — skipping CNPG operator deployment"
        log_info "  PostgreSQL targets are managed externally"
        return 0
    fi

    log_info "Deploying PostgreSQL via operator-based reference ..."
    [[ -n "$cluster_filter" ]] && log_info "  Cluster filter: ${cluster_filter}"

    (
        cd "${OPERATOR_BASED_DIR}/postgresql"
        CAMUNDA_NAMESPACE="${NAMESPACE}" \
        CLUSTER_FILTER="${cluster_filter}" \
        bash deploy.sh "${CNPG_OPERATOR_NAMESPACE}"
    )

    log_success "PostgreSQL deployment complete${cluster_filter:+ (${cluster_filter})}"
}

# Deploy ECK operator + Elasticsearch cluster.
# Uses the migration-specific ECK manifest (with path.repo + backup PVC mount).
deploy_elasticsearch() {
    if is_external_es; then
        log_info "ES_TARGET_MODE=external — skipping ECK operator deployment"
        log_info "  Elasticsearch target: ${EXTERNAL_ES_HOST:-<not set>}:${EXTERNAL_ES_PORT:-443}"
        return 0
    fi

    log_info "Deploying Elasticsearch via operator-based reference ..."

    # Render migration-specific ECK cluster manifest (needs envsubst for variables)
    local rendered_eck="${STATE_DIR}/eck-cluster-rendered.yml"
    envsubst < "${MANIFESTS_DIR}/eck-cluster.yml" > "$rendered_eck"

    (
        cd "${OPERATOR_BASED_DIR}/elasticsearch"
        CAMUNDA_NAMESPACE="${NAMESPACE}" \
        ELASTICSEARCH_CLUSTER_FILE="$rendered_eck" \
        bash deploy.sh "${ECK_OPERATOR_NAMESPACE}"
    )

    log_success "Elasticsearch deployment complete"
}

# Deploy Keycloak operator + Keycloak CR.
# Automatically selects domain vs no-domain variant based on CAMUNDA_DOMAIN.
deploy_keycloak() {
    log_info "Deploying Keycloak via operator-based reference ..."

    local kc_config
    if [[ -n "${CUSTOM_KEYCLOAK_CONFIG_FILE:-}" ]]; then
        kc_config="${CUSTOM_KEYCLOAK_CONFIG_FILE}"
        log_info "  Using custom Keycloak CR: ${kc_config}"
    elif [[ -n "${CAMUNDA_DOMAIN:-}" && "${CAMUNDA_DOMAIN}" != "localhost" ]]; then
        kc_config="${OPERATOR_BASED_DIR}/keycloak/keycloak-instance-domain-nginx.yml"
        log_info "  Using domain configuration: ${CAMUNDA_DOMAIN}"
    else
        kc_config="${OPERATOR_BASED_DIR}/keycloak/keycloak-instance-no-domain.yml"
        log_info "  Using no-domain (port-forward) configuration"
    fi

    (
        cd "${OPERATOR_BASED_DIR}/keycloak"
        CAMUNDA_NAMESPACE="${NAMESPACE}" \
        KEYCLOAK_CONFIG_FILE="$kc_config" \
        bash deploy.sh
    )

    log_success "Keycloak deployment complete"
}

# Render an envsubst template to a file. Used for helm values containing ${CAMUNDA_DOMAIN}.
# Usage: render_template <source> <destination>
render_template() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    envsubst < "$src" > "$dst"
}

# Get the appropriate Helm values file for a component.
# For files containing envsubst vars (keycloak domain), renders to .state/ first.
# Usage: get_helm_values <component>
# Output: path to the values file (stdout)
get_helm_values() {
    local component="$1"
    case "$component" in
        identity)
            echo "${OPERATOR_BASED_DIR}/postgresql/camunda-identity-values.yml"
            ;;
        webmodeler)
            echo "${OPERATOR_BASED_DIR}/postgresql/camunda-webmodeler-values.yml"
            ;;
        elasticsearch)
            echo "${OPERATOR_BASED_DIR}/elasticsearch/camunda-elastic-values.yml"
            ;;
        keycloak-domain)
            # Contains ${CAMUNDA_DOMAIN} — must be rendered
            local rendered="${STATE_DIR}/keycloak-helm-values.yml"
            render_template "${OPERATOR_BASED_DIR}/keycloak/camunda-keycloak-domain-values.yml" "$rendered"
            echo "$rendered"
            ;;
        keycloak-no-domain)
            echo "${OPERATOR_BASED_DIR}/keycloak/camunda-keycloak-no-domain-values.yml"
            ;;
    esac
}

# =============================================================================
# PostgreSQL Introspection
# =============================================================================

# Introspect a Bitnami PostgreSQL StatefulSet.
# Usage: introspect_pg <sts-name>
# Exports: PG_IMAGE, PG_STORAGE_SIZE, PG_REPLICAS, PG_RESOURCES, PG_VERSION
introspect_pg() {
    local sts_name="$1"
    log_info "Introspecting StatefulSet ${sts_name} ..."

    if ! kubectl get statefulset "${sts_name}" -n "${NAMESPACE}" &>/dev/null; then
        log_error "StatefulSet ${sts_name} not found"
        return 1
    fi

    local json
    json=$(kubectl get statefulset "${sts_name}" -n "${NAMESPACE}" -o json)

    export PG_IMAGE;       PG_IMAGE=$(echo "$json" | jq -r '.spec.template.spec.containers[0].image')
    export PG_STORAGE_SIZE; PG_STORAGE_SIZE=$(echo "$json" | jq -r '.spec.volumeClaimTemplates[0].spec.resources.requests.storage // "8Gi"')
    export PG_REPLICAS;    PG_REPLICAS=$(echo "$json" | jq -r '.spec.replicas // 1')
    export PG_VERSION;     PG_VERSION=$(echo "$PG_IMAGE" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "15")

    log_success "Image: ${PG_IMAGE}"
    log_success "Storage: ${PG_STORAGE_SIZE}, Replicas: ${PG_REPLICAS}, Version: ${PG_VERSION}"
}

# Detect the Bitnami PG StatefulSet name for a component.
# Usage: detect_pg_sts identity|keycloak|webmodeler
# Returns the sts name via stdout, or returns 1 if not found.
detect_pg_sts() {
    local component="$1"
    local release="${CAMUNDA_RELEASE_NAME}"
    local ns="${NAMESPACE}"

    local candidates=()
    case "$component" in
        identity)
            candidates=("${release}-postgresql" "${release}-identity-postgresql")
            ;;
        keycloak)
            candidates=("${release}-keycloak-postgresql" "${release}-postgresql-keycloak")
            ;;
        webmodeler)
            candidates=("${release}-postgresql-web-modeler" "${release}-web-modeler-postgresql"
                        "${release}-webmodeler-postgresql")
            ;;
    esac

    for name in "${candidates[@]}"; do
        if kubectl get statefulset "$name" -n "$ns" &>/dev/null; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

# Get PG password from an existing Bitnami secret.
# Usage: get_bitnami_pg_password <secret-name>
get_bitnami_pg_password() {
    local secret_name="$1"
    kubectl get secret "$secret_name" -n "${NAMESPACE}" \
        -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d 2>/dev/null \
    || kubectl get secret "$secret_name" -n "${NAMESPACE}" \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null \
    || echo ""
}

# =============================================================================
# Elasticsearch Introspection
# =============================================================================

introspect_es() {
    log_info "Introspecting Elasticsearch ..."

    local sts_name
    sts_name=$(kubectl get statefulset -n "${NAMESPACE}" -o name 2>/dev/null \
        | grep -E "elasticsearch" | head -1 | sed 's|statefulset.apps/||' || echo "")

    if [[ -z "$sts_name" ]]; then
        log_error "No Elasticsearch StatefulSet found"
        return 1
    fi

    local json
    json=$(kubectl get statefulset "${sts_name}" -n "${NAMESPACE}" -o json)

    export ES_STS_NAME="$sts_name"
    export ES_IMAGE;        ES_IMAGE=$(echo "$json" | jq -r '.spec.template.spec.containers[0].image')
    export ES_STORAGE_SIZE; ES_STORAGE_SIZE=$(echo "$json" | jq -r '.spec.volumeClaimTemplates[0].spec.resources.requests.storage // "30Gi"')
    export ES_REPLICAS;     ES_REPLICAS=$(echo "$json" | jq -r '.spec.replicas // 1')
    export ES_VERSION;      ES_VERSION=$(echo "$ES_IMAGE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "8.15.0")

    log_success "ES STS: ${sts_name}, Image: ${ES_IMAGE}"
    log_success "Storage: ${ES_STORAGE_SIZE}, Replicas: ${ES_REPLICAS}, Version: ${ES_VERSION}"
}

# =============================================================================
# Backup PVC
# =============================================================================

ensure_backup_pvc() {
    if kubectl get pvc "${BACKUP_PVC}" -n "${NAMESPACE}" &>/dev/null; then
        log_success "Backup PVC ${BACKUP_PVC} already exists"
        return 0
    fi
    log_info "Creating backup PVC ${BACKUP_PVC} ..."
    apply_template "${MANIFESTS_DIR}/backup-pvc.yml"
    log_success "Backup PVC created"
}

# =============================================================================
# PostgreSQL Backup / Restore (via Kubernetes Jobs)
# =============================================================================

# Run a PG backup job.
# Expects exports: COMPONENT, PG_HOST, PG_PORT, PG_DATABASE, PG_USERNAME,
#                  PG_SECRET_NAME, PG_IMAGE, BACKUP_PVC, NAMESPACE, TIMESTAMP
backup_pg() {
    ensure_backup_pvc
    # shellcheck disable=SC2153
    export JOB_NAME="${COMPONENT}-pg-backup-${TIMESTAMP}"
    run_job "${JOBS_DIR}/pg-backup.job.yml" "${JOB_NAME}"
}

# Run a PG restore job.
# Expects exports: COMPONENT, TARGET_PG_HOST, TARGET_PG_PORT, TARGET_PG_DATABASE,
#                  TARGET_PG_USER, DB_SECRET_NAME, PG_IMAGE, BACKUP_PVC,
#                  BACKUP_FILE, NAMESPACE, TIMESTAMP
restore_pg() {
    export JOB_NAME="${COMPONENT}-pg-restore-${TIMESTAMP}"
    run_job "${JOBS_DIR}/pg-restore.job.yml" "${JOB_NAME}"
}

# =============================================================================
# Elasticsearch Backup / Restore (via Kubernetes Jobs)
# =============================================================================

# Run an ES backup job using the snapshot API.
# Expects: ES_HOST, ES_PORT, SNAPSHOT_REPO, SNAPSHOT_NAME, ES_SECRET_NAME,
#          BACKUP_PVC, NAMESPACE, TIMESTAMP
backup_es() {
    ensure_backup_pvc
    export JOB_NAME="es-backup-${TIMESTAMP}"
    run_job "${JOBS_DIR}/es-backup.job.yml" "${JOB_NAME}"
}

# Run an ES restore job.
# Expects: TARGET_ES_HOST, TARGET_ES_PORT, SNAPSHOT_REPO, SNAPSHOT_NAME,
#          ES_SECRET_NAME, NAMESPACE, TIMESTAMP
restore_es() {
    export JOB_NAME="es-restore-${TIMESTAMP}"
    run_job "${JOBS_DIR}/es-restore.job.yml" "${JOB_NAME}"
}

# =============================================================================
# Scale Management
# =============================================================================

# Save current replica counts and scale to 0.
# Usage: freeze_components <deployment-name> [<deployment-name> ...]
freeze_components() {
    local state_file="${STATE_DIR}/replica-counts.env"
    : > "$state_file"

    for deploy in "$@"; do
        local kind="deployment"
        # Support StatefulSets (prefix with "sts/")
        if [[ "$deploy" == sts/* ]]; then
            kind="statefulset"
            deploy="${deploy#sts/}"
        fi

        local replicas
        replicas=$(kubectl get "$kind" "$deploy" -n "${NAMESPACE}" \
            -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        echo "export SAVED_${deploy//-/_}=${replicas}" >> "$state_file"

        log_info "Scaling ${kind} ${deploy} to 0 (was ${replicas})"
        kubectl scale "$kind" "$deploy" -n "${NAMESPACE}" --replicas=0
    done

    # Wait for pods to terminate
    sleep 5
    log_success "All components frozen"
}

# Restore replica counts from saved state.
unfreeze_components() {
    local state_file="${STATE_DIR}/replica-counts.env"
    if [[ ! -f "$state_file" ]]; then
        log_warn "No saved replica counts found"
        return 0
    fi

    # shellcheck source=/dev/null
    source "$state_file"

    for deploy in "$@"; do
        local kind="deployment"
        if [[ "$deploy" == sts/* ]]; then
            kind="statefulset"
            deploy="${deploy#sts/}"
        fi

        local var_name="SAVED_${deploy//-/_}"
        local replicas="${!var_name:-1}"

        log_info "Scaling ${kind} ${deploy} to ${replicas}"
        kubectl scale "$kind" "$deploy" -n "${NAMESPACE}" --replicas="${replicas}"
    done

    log_success "All components unfrozen"
}

# =============================================================================
# Helm Management
# =============================================================================

helm_backup() {
    log_info "Saving current Helm values ..."
    helm get values "${CAMUNDA_RELEASE_NAME}" -n "${NAMESPACE}" -o yaml \
        > "${STATE_DIR}/helm-values-backup.yml"
    log_success "Helm values saved to ${STATE_DIR}/helm-values-backup.yml"
}

# Apply migration helm values on top of existing values.
# Usage: helm_upgrade <values-file> [<values-file> ...]
helm_upgrade() {
    local values_args=()
    for f in "$@"; do
        values_args+=(-f "$f")
    done

    log_info "Running helm upgrade ..."
    helm upgrade "${CAMUNDA_RELEASE_NAME}" camunda/camunda-platform \
        -n "${NAMESPACE}" \
        --version "${CAMUNDA_HELM_CHART_VERSION}" \
        --reuse-values \
        "${values_args[@]}"

    log_success "Helm upgrade complete"
}

helm_rollback_from_backup() {
    local backup="${STATE_DIR}/helm-values-backup.yml"
    if [[ ! -f "$backup" ]]; then
        log_error "No helm values backup found"
        return 1
    fi

    log_info "Rolling back Helm to pre-migration values ..."
    helm upgrade "${CAMUNDA_RELEASE_NAME}" camunda/camunda-platform \
        -n "${NAMESPACE}" \
        --version "${CAMUNDA_HELM_CHART_VERSION}" \
        -f "$backup"

    log_success "Helm rollback complete"
}

# =============================================================================
# State persistence helpers
# =============================================================================

save_state() {
    local key="$1" value="$2"
    echo "export ${key}=\"${value}\"" >> "${STATE_DIR}/migration.env"
}

load_state() {
    if [[ -f "${STATE_DIR}/migration.env" ]]; then
        # shellcheck source=/dev/null
        source "${STATE_DIR}/migration.env"
    fi
}

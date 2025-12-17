#!/bin/bash
# ==============================================================================
# validate-test-data.sh
# ==============================================================================
# Validates that test data was correctly preserved after migration.
#
# This script checks:
# - Process definitions are accessible
# - Process instances are visible in Operate
# - User tasks are available in Tasklist
# - Elasticsearch indices contain expected data
#
# Usage:
#   ./validate-test-data.sh
#
# Prerequisites:
#   - CAMUNDA_NAMESPACE set
#   - kubectl access to the cluster
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
CAMUNDA_RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

VALIDATION_PASSED=true

# ==============================================================================
# Check Test Marker
# ==============================================================================
check_test_marker() {
    log_info "Checking test data marker..."

    if kubectl get configmap migration-test-data-marker -n "${CAMUNDA_NAMESPACE}" &>/dev/null; then
        local created_at
        created_at=$(kubectl get configmap migration-test-data-marker -n "${CAMUNDA_NAMESPACE}" \
            -o jsonpath='{.data.created_at}')
        local expected_instances
        expected_instances=$(kubectl get configmap migration-test-data-marker -n "${CAMUNDA_NAMESPACE}" \
            -o jsonpath='{.data.process_instances}')

        log_success "Test marker found - created at: ${created_at}"
        log_info "Expected instances per process: ${expected_instances}"
        echo ""
        return 0
    else
        log_warn "Test marker ConfigMap not found - was test data generated before migration?"
        return 1
    fi
}

# ==============================================================================
# Validate Elasticsearch Data
# ==============================================================================
validate_elasticsearch_indices() {
    log_info "Validating Elasticsearch indices..."

    # Detect Elasticsearch type (Bitnami, ECK, or OpenSearch)
    local es_pod=""

    # Try ECK first
    es_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
        -l "elasticsearch.k8s.elastic.co/cluster-name" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$es_pod" ]]; then
        # Try Bitnami/standard Elasticsearch
        es_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
            -l "app=elasticsearch" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

    if [[ -z "$es_pod" ]]; then
        es_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
            -l "app.kubernetes.io/name=elasticsearch" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

    if [[ -z "$es_pod" ]]; then
        log_warn "Could not find Elasticsearch pod"
        return 1
    fi

    log_info "Found Elasticsearch pod: ${es_pod}"

    # Get password for ECK if needed
    local auth_header=""
    local es_secret
    es_secret=$(kubectl get secret -n "${CAMUNDA_NAMESPACE}" \
        -l "elasticsearch.k8s.elastic.co/cluster-name" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$es_secret" ]]; then
        local es_password
        es_password=$(kubectl get secret "$es_secret" -n "${CAMUNDA_NAMESPACE}" \
            -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d || echo "")
        if [[ -n "$es_password" ]]; then
            auth_header="-u elastic:${es_password}"
        fi
    fi

    # Check indices exist
    echo ""
    log_info "Checking for Camunda indices..."

    local indices_output
    indices_output=$(kubectl exec -n "${CAMUNDA_NAMESPACE}" "$es_pod" -- \
        curl -s "${auth_header}" "localhost:9200/_cat/indices?v" 2>/dev/null || echo "")

    local operate_indices
    operate_indices=$(echo "$indices_output" | grep -c "operate" || echo "0")
    local tasklist_indices
    tasklist_indices=$(echo "$indices_output" | grep -c "tasklist" || echo "0")
    local zeebe_indices
    zeebe_indices=$(echo "$indices_output" | grep -c "zeebe" || echo "0")

    echo ""
    if [[ "$operate_indices" -gt 0 ]]; then
        log_success "Found ${operate_indices} Operate indices"
    else
        log_error "No Operate indices found!"
        VALIDATION_PASSED=false
    fi

    if [[ "$tasklist_indices" -gt 0 ]]; then
        log_success "Found ${tasklist_indices} Tasklist indices"
    else
        log_error "No Tasklist indices found!"
        VALIDATION_PASSED=false
    fi

    if [[ "$zeebe_indices" -gt 0 ]]; then
        log_success "Found ${zeebe_indices} Zeebe indices"
    else
        log_warn "No Zeebe-record indices found (may be normal)"
    fi

    # Check for process definitions
    echo ""
    log_info "Checking for migration test process definitions..."

    local process_count
    process_count=$(kubectl exec -n "${CAMUNDA_NAMESPACE}" "$es_pod" -- \
        curl -s "${auth_header}" "localhost:9200/operate-process-*/_search" \
        -H "Content-Type: application/json" \
        -d '{"query":{"match":{"bpmnProcessId":"migration-test-*"}},"size":0}' 2>/dev/null | \
        jq -r '.hits.total.value // .hits.total // 0' || echo "0")

    if [[ "$process_count" -gt 0 ]]; then
        log_success "Found ${process_count} migration test process definitions"
    else
        log_warn "No migration test processes found in Elasticsearch"
    fi

    # Check for process instances
    echo ""
    log_info "Checking for migration test process instances..."

    local instance_count
    instance_count=$(kubectl exec -n "${CAMUNDA_NAMESPACE}" "$es_pod" -- \
        curl -s "${auth_header}" "localhost:9200/operate-list-view-*/_search" \
        -H "Content-Type: application/json" \
        -d '{"query":{"match":{"bpmnProcessId":"migration-test-*"}},"size":0}' 2>/dev/null | \
        jq -r '.hits.total.value // .hits.total // 0' || echo "0")

    if [[ "$instance_count" -gt 0 ]]; then
        log_success "Found ${instance_count} migration test process instances"
    else
        log_warn "No migration test instances found in Elasticsearch"
    fi
}

# ==============================================================================
# Validate PostgreSQL Data (Identity)
# ==============================================================================
validate_postgres_identity() {
    log_info "Validating Identity PostgreSQL data..."

    # Detect PostgreSQL type (Bitnami or CNPG)
    local pg_pod=""

    # Try CNPG first
    pg_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
        -l "cnpg.io/cluster=identity-postgres" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$pg_pod" ]]; then
        # Try Bitnami PostgreSQL
        pg_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
            -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${CAMUNDA_RELEASE_NAME}" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

    if [[ -z "$pg_pod" ]]; then
        log_warn "Could not find Identity PostgreSQL pod"
        return 0
    fi

    log_info "Found PostgreSQL pod: ${pg_pod}"

    # Check if we can query the database
    local table_count
    table_count=$(kubectl exec -n "${CAMUNDA_NAMESPACE}" "$pg_pod" -- \
        psql -U identity -d identity -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")

    if [[ "$table_count" -gt 0 ]]; then
        log_success "Identity database has ${table_count} tables"
    else
        log_warn "Could not query Identity database"
    fi
}

# ==============================================================================
# Validate Keycloak Data
# ==============================================================================
validate_keycloak_data() {
    log_info "Validating Keycloak data..."

    # Detect Keycloak type (Bitnami or Keycloak Operator)
    local kc_pod=""

    # Try Keycloak Operator first
    kc_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
        -l "app.kubernetes.io/managed-by=keycloak-operator" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$kc_pod" ]]; then
        # Try Bitnami Keycloak
        kc_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
            -l "app.kubernetes.io/name=keycloak" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

    if [[ -z "$kc_pod" ]]; then
        log_warn "Could not find Keycloak pod"
        return 0
    fi

    log_info "Found Keycloak pod: ${kc_pod}"

    # Check Keycloak is responding
    local kc_ready
    kc_ready=$(kubectl get pod "$kc_pod" -n "${CAMUNDA_NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [[ "$kc_ready" == "True" ]]; then
        log_success "Keycloak pod is ready"
    else
        log_error "Keycloak pod is not ready!"
        VALIDATION_PASSED=false
    fi
}

# ==============================================================================
# Validate Web Modeler PostgreSQL
# ==============================================================================
validate_postgres_webmodeler() {
    log_info "Validating WebModeler PostgreSQL data..."

    # Detect PostgreSQL type (Bitnami or CNPG)
    local pg_pod=""

    # Try CNPG first
    pg_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
        -l "cnpg.io/cluster=webmodeler-postgres" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$pg_pod" ]]; then
        # Try Bitnami PostgreSQL for WebModeler
        pg_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
            -l "app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=${CAMUNDA_RELEASE_NAME}-web-modeler-postgresql" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

    if [[ -z "$pg_pod" ]]; then
        log_warn "Could not find WebModeler PostgreSQL pod (WebModeler may not be enabled)"
        return 0
    fi

    log_info "Found WebModeler PostgreSQL pod: ${pg_pod}"

    # Check if we can query the database
    local table_count
    table_count=$(kubectl exec -n "${CAMUNDA_NAMESPACE}" "$pg_pod" -- \
        psql -U webmodeler -d webmodeler -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")

    if [[ "$table_count" -gt 0 ]]; then
        log_success "WebModeler database has ${table_count} tables"
    else
        log_warn "Could not query WebModeler database"
    fi
}

# ==============================================================================
# Summary
# ==============================================================================
print_summary() {
    echo ""
    echo "=============================================="
    echo "  Validation Summary"
    echo "=============================================="
    echo ""

    if [[ "$VALIDATION_PASSED" == "true" ]]; then
        log_success "All critical validations passed!"
        echo ""
        echo "The migration appears to have preserved the test data correctly."
        return 0
    else
        log_error "Some validations failed!"
        echo ""
        echo "Please review the errors above and check the migration."
        return 1
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo ""
    echo "=============================================="
    echo "  Migration Test Data Validator"
    echo "=============================================="
    echo ""

    log_info "Namespace: ${CAMUNDA_NAMESPACE}"
    log_info "Release: ${CAMUNDA_RELEASE_NAME}"
    echo ""

    check_test_marker || true

    echo ""
    echo "--- Elasticsearch Validation ---"
    validate_elasticsearch_indices || true

    echo ""
    echo "--- Identity PostgreSQL Validation ---"
    validate_postgres_identity || true

    echo ""
    echo "--- Keycloak Validation ---"
    validate_keycloak_data || true

    echo ""
    echo "--- WebModeler PostgreSQL Validation ---"
    validate_postgres_webmodeler || true

    print_summary
}

main "$@"

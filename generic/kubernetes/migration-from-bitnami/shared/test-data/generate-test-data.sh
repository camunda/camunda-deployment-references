#!/bin/bash
# ==============================================================================
# generate-test-data.sh
# ==============================================================================
# Generates test data for migration validation in a Camunda 8 cluster.
#
# This script supports two modes:
# 1. BENCHMARK mode (default): Uses camunda-8-benchmark Docker image
#    - Deploys typical_process with 10 service tasks
#    - Creates process instances at a configurable rate
#    - Auto-completes jobs to populate Elasticsearch indices
#
# 2. ZBCTL mode: Uses zbctl to deploy processes and create instances
#    - Deploys custom BPMN files with user tasks and timers
#    - Creates instances that remain active for validation
#
# Usage:
#   ./generate-test-data.sh [--mode benchmark|zbctl]
#
# Environment variables:
#   CAMUNDA_NAMESPACE - Kubernetes namespace (default: camunda)
#   CAMUNDA_RELEASE_NAME - Helm release name (default: camunda)
#   TEST_DATA_MODE - benchmark or zbctl (default: benchmark)
#   BENCHMARK_DURATION - How long to run benchmark in seconds (default: 60)
#   BENCHMARK_PI_PER_SECOND - Process instances per second (default: 5)
#   NUM_PROCESS_INSTANCES - Number of instances for zbctl mode (default: 5)
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BPMN_DIR="${SCRIPT_DIR}/bpmn"

# Default values
CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
CAMUNDA_RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
TEST_DATA_MODE="${TEST_DATA_MODE:-benchmark}"
BENCHMARK_DURATION="${BENCHMARK_DURATION:-60}"
BENCHMARK_PI_PER_SECOND="${BENCHMARK_PI_PER_SECOND:-5}"
NUM_PROCESS_INSTANCES="${NUM_PROCESS_INSTANCES:-5}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            TEST_DATA_MODE="$2"
            shift 2
            ;;
        --duration)
            BENCHMARK_DURATION="$2"
            shift 2
            ;;
        --rate)
            BENCHMARK_PI_PER_SECOND="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==============================================================================
# BENCHMARK MODE: Use camunda-8-benchmark
# ==============================================================================
run_benchmark_mode() {
    log_info "Using camunda-8-benchmark to generate test data..."

    # Create the benchmark job
    cat <<EOF | kubectl apply -n "${CAMUNDA_NAMESPACE}" -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: migration-test-data-generator
  labels:
    app: migration-test-data
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 3
  template:
    metadata:
      labels:
        app: migration-test-data
    spec:
      restartPolicy: Never
      containers:
        - name: benchmark
          image: camundacommunityhub/camunda-8-benchmark:main
          env:
            - name: CAMUNDA_CLIENT_MODE
              value: "self-managed"
            - name: CAMUNDA_CLIENT_ZEEBE_BASE_URL
              value: "http://${CAMUNDA_RELEASE_NAME}-zeebe-gateway:26500"
            - name: CAMUNDA_CLIENT_ZEEBE_GRPC_ADDRESS
              value: "http://${CAMUNDA_RELEASE_NAME}-zeebe-gateway:26500"
            - name: CAMUNDA_CLIENT_ZEEBE_PREFER_REST_OVER_GRPC
              value: "false"
            - name: BENCHMARK_START_PROCESSES
              value: "true"
            - name: BENCHMARK_START_PI_PER_SECOND
              value: "${BENCHMARK_PI_PER_SECOND}"
            - name: BENCHMARK_AUTO_DEPLOY_PROCESS
              value: "true"
            - name: BENCHMARK_BPMN_PROCESS_ID
              value: "benchmark"
            - name: BENCHMARK_START_WORKERS
              value: "true"
            - name: BENCHMARK_JOB_TYPE
              value: "benchmark-task"
            - name: BENCHMARK_TASK_COMPLETION_DELAY
              value: "100"
            - name: BENCHMARK_WARMUP_PHASE_DURATION_MILLIS
              value: "10000"
            - name: BENCHMARK_START_RATE_ADJUSTMENT_STRATEGY
              value: "none"
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1
              memory: 1Gi
EOF

    log_info "Waiting for benchmark job to start..."
    sleep 10

    # Wait for the pod to be running
    log_info "Waiting for benchmark pod to be ready..."
    kubectl wait --for=condition=ready pod \
        -l job-name=migration-test-data-generator \
        -n "${CAMUNDA_NAMESPACE}" \
        --timeout=120s || true

    # Let the benchmark run for the specified duration
    log_info "Benchmark is running, waiting ${BENCHMARK_DURATION}s for data generation..."
    sleep "${BENCHMARK_DURATION}"

    # Show job status and logs
    log_info "Benchmark job status:"
    kubectl get job migration-test-data-generator -n "${CAMUNDA_NAMESPACE}" || true

    log_info "Benchmark logs (last 30 lines):"
    kubectl logs job/migration-test-data-generator -n "${CAMUNDA_NAMESPACE}" --tail=30 || true

    # Delete the job (we just needed it to generate some data)
    log_info "Cleaning up benchmark job..."
    kubectl delete job migration-test-data-generator -n "${CAMUNDA_NAMESPACE}" --ignore-not-found=true || true

    log_success "Benchmark data generation completed"
}

# ==============================================================================
# ZBCTL MODE: Use zbctl for custom processes
# ==============================================================================
setup_zeebe_access() {
    log_info "Setting up Zeebe gateway access..."

    USE_KUBECTL_EXEC=true
    export USE_KUBECTL_EXEC
}

get_gateway_pod() {
    local gateway_pod
    gateway_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
        -l "app.kubernetes.io/component=zeebe-gateway" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$gateway_pod" ]]; then
        gateway_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
            -l "app=camunda-platform,component=zeebe-gateway" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

    echo "$gateway_pod"
}

deploy_process_zbctl() {
    local bpmn_file="$1"
    local process_name=$(basename "$bpmn_file" .bpmn)

    log_info "Deploying process: ${process_name}"

    local gateway_pod
    gateway_pod=$(get_gateway_pod)

    if [[ -z "$gateway_pod" ]]; then
        log_error "Could not find Zeebe gateway pod"
        return 1
    fi

    # Copy BPMN file to pod
    kubectl cp "$bpmn_file" "${CAMUNDA_NAMESPACE}/${gateway_pod}:/tmp/${process_name}.bpmn"

    # Deploy using zbctl in pod
    kubectl exec -n "${CAMUNDA_NAMESPACE}" "$gateway_pod" -- \
        zbctl deploy "/tmp/${process_name}.bpmn" --insecure 2>/dev/null || \
    kubectl exec -n "${CAMUNDA_NAMESPACE}" "$gateway_pod" -- \
        /usr/local/bin/zbctl deploy "/tmp/${process_name}.bpmn" --insecure || true

    log_success "Deployed: ${process_name}"
}

create_process_instance_zbctl() {
    local process_id="$1"
    local variables="${2:-{}}"

    local gateway_pod
    gateway_pod=$(get_gateway_pod)

    if [[ -z "$gateway_pod" ]]; then
        log_error "Could not find Zeebe gateway pod"
        return 1
    fi

    kubectl exec -n "${CAMUNDA_NAMESPACE}" "$gateway_pod" -- \
        zbctl create instance "$process_id" --variables "$variables" --insecure 2>/dev/null || \
    kubectl exec -n "${CAMUNDA_NAMESPACE}" "$gateway_pod" -- \
        /usr/local/bin/zbctl create instance "$process_id" --variables "$variables" --insecure || true
}

run_zbctl_mode() {
    log_info "Using zbctl to generate test data with custom processes..."

    setup_zeebe_access

    # Deploy BPMN files from the bpmn directory
    if [[ -d "$BPMN_DIR" ]]; then
        for bpmn_file in "${BPMN_DIR}"/*.bpmn; do
            if [[ -f "$bpmn_file" ]]; then
                deploy_process_zbctl "$bpmn_file"
            fi
        done
    else
        log_warn "BPMN directory not found: $BPMN_DIR"
    fi

    sleep 5  # Wait for deployment to propagate

    # Create process instances
    local timestamp
    timestamp=$(date +%s)

    log_info "Creating ${NUM_PROCESS_INSTANCES} instances for each process..."

    # User task instances (will remain active)
    for i in $(seq 1 "$NUM_PROCESS_INSTANCES"); do
        local variables="{\"migrationTest\": true, \"instanceNumber\": ${i}, \"timestamp\": ${timestamp}}"
        create_process_instance_zbctl "migration-test-user-task" "$variables" || true
        sleep 1
    done

    # Timer instances (will remain waiting)
    for i in $(seq 1 "$NUM_PROCESS_INSTANCES"); do
        local variables="{\"migrationTest\": true, \"timerInstance\": ${i}, \"timestamp\": ${timestamp}}"
        create_process_instance_zbctl "migration-test-timer" "$variables" || true
        sleep 1
    done

    log_success "Created process instances via zbctl"
}

# ==============================================================================
# Validate Elasticsearch Data
# ==============================================================================
validate_elasticsearch_data() {
    log_info "Validating Elasticsearch data..."

    local es_pod
    es_pod=$(kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
        -l "app=elasticsearch" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
        kubectl get pods -n "${CAMUNDA_NAMESPACE}" \
        -l "app.kubernetes.io/name=elasticsearch" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
        echo "")

    if [[ -z "$es_pod" ]]; then
        log_warn "Could not find Elasticsearch pod for validation"
        return 0
    fi

    # Check for process indices
    log_info "Checking Elasticsearch indices..."
    kubectl exec -n "${CAMUNDA_NAMESPACE}" "$es_pod" -- \
        curl -s "localhost:9200/_cat/indices?v" 2>/dev/null | grep -E "(operate|tasklist|zeebe)" || true

    # Count documents
    log_info "Counting documents in process indices..."
    local doc_count
    doc_count=$(kubectl exec -n "${CAMUNDA_NAMESPACE}" "$es_pod" -- \
        curl -s "localhost:9200/operate-process-*/_count" 2>/dev/null | jq -r '.count // 0' || echo "0")

    log_success "Found ${doc_count} documents in operate-process indices"

    local instance_count
    instance_count=$(kubectl exec -n "${CAMUNDA_NAMESPACE}" "$es_pod" -- \
        curl -s "localhost:9200/operate-list-view-*/_count" 2>/dev/null | jq -r '.count // 0' || echo "0")

    log_success "Found ${instance_count} documents in operate-list-view indices"
}

# ==============================================================================
# Create Test Marker for Validation
# ==============================================================================
create_test_marker() {
    log_info "Creating test marker ConfigMap for migration validation..."

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local generator_info
    if [[ "$TEST_DATA_MODE" == "benchmark" ]]; then
        generator_info="camunda-8-benchmark"
    else
        generator_info="zbctl"
    fi

    kubectl create configmap migration-test-data-marker \
        --namespace="${CAMUNDA_NAMESPACE}" \
        --from-literal=created_at="${timestamp}" \
        --from-literal=generator="${generator_info}" \
        --from-literal=mode="${TEST_DATA_MODE}" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_success "Created test marker ConfigMap"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo ""
    echo "=============================================="
    echo "  Migration Test Data Generator"
    echo "=============================================="
    echo ""

    log_info "Namespace: ${CAMUNDA_NAMESPACE}"
    log_info "Release: ${CAMUNDA_RELEASE_NAME}"
    log_info "Mode: ${TEST_DATA_MODE}"
    echo ""

    case "${TEST_DATA_MODE}" in
        benchmark)
            log_info "Duration: ${BENCHMARK_DURATION}s"
            log_info "Rate: ${BENCHMARK_PI_PER_SECOND} PI/s"
            run_benchmark_mode
            ;;
        zbctl)
            log_info "Instances per process: ${NUM_PROCESS_INSTANCES}"
            run_zbctl_mode
            ;;
        *)
            log_error "Unknown mode: ${TEST_DATA_MODE}"
            log_info "Valid modes: benchmark, zbctl"
            exit 1
            ;;
    esac

    sleep 5

    validate_elasticsearch_data

    create_test_marker

    echo ""
    log_success "Test data generation completed!"
    echo ""
    echo "After migration, you can validate by checking:"
    echo "  1. Process definitions exist in Operate"
    echo "  2. Process instances are visible"
    echo "  3. Elasticsearch indices contain data"
    echo ""
}

main "$@"

#!/usr/bin/env bash
# =============================================================================
# Local test runner for migration seed/verify jobs on Kind.
#
# Usage:
#   ./local-test.sh              # Full run: reset cluster, deploy, seed, benchmark, verify
#   ./local-test.sh seed-only    # Re-apply seed + benchmark jobs on existing deployment
#   ./local-test.sh verify-only  # Run verify job on existing deployment
#   ./local-test.sh deploy-only  # Deploy Camunda (skip cluster create)
#   ./local-test.sh teardown     # Delete the Kind cluster
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="camunda-platform-local"
NAMESPACE="camunda"
RELEASE_NAME="camunda"
KIND_CONFIG="${SCRIPT_DIR}/kind-cluster-config.yaml"
VALUES_FILE="${SCRIPT_DIR}/bitnami-values.yml"
SEED_JOB="${SCRIPT_DIR}/seed-test-data-job.yml"
BENCHMARK_JOB="${SCRIPT_DIR}/benchmark-job.yml"
VERIFY_JOB="${SCRIPT_DIR}/verify-test-data-job.yml"

log() { echo "$(date +%H:%M:%S) | $*"; }
err() { log "ERROR: $*" >&2; }

# ── Helpers ──────────────────────────────────────────────────────────────────
ensure_cluster() {
    if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
        log "Kind cluster '${CLUSTER_NAME}' already exists"
        kubectl config use-context "kind-${CLUSTER_NAME}"
    else
        log "Creating Kind cluster '${CLUSTER_NAME}'..."
        kind create cluster --config "${KIND_CONFIG}"
        kubectl cluster-info --context "kind-${CLUSTER_NAME}"
    fi
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
}

create_pull_secrets() {
    log "Creating pull secrets from local Docker config..."

    # registry.camunda.cloud
    if kubectl get secret registry-camunda-cloud -n "${NAMESPACE}" &>/dev/null; then
        log "  registry-camunda-cloud secret already exists"
    else
        kubectl create secret generic registry-camunda-cloud \
            --from-file=.dockerconfigjson="${HOME}/.docker/config.json" \
            --type=kubernetes.io/dockerconfigjson \
            --namespace="${NAMESPACE}"
        log "  Created registry-camunda-cloud"
    fi

    # index-docker-io (use same docker config — it contains docker.io creds)
    if kubectl get secret index-docker-io -n "${NAMESPACE}" &>/dev/null; then
        log "  index-docker-io secret already exists"
    else
        kubectl create secret generic index-docker-io \
            --from-file=.dockerconfigjson="${HOME}/.docker/config.json" \
            --type=kubernetes.io/dockerconfigjson \
            --namespace="${NAMESPACE}"
        log "  Created index-docker-io"
    fi
}

create_identity_secrets() {
    log "Creating identity secrets (camunda-credentials)..."
    CAMUNDA_NAMESPACE="${NAMESPACE}" \
        "${SCRIPT_DIR}/create-identity-secrets.sh"
}

deploy_camunda() {
    log "Adding Camunda Helm repo..."
    helm repo add camunda https://helm.camunda.io 2>/dev/null || true
    helm repo update

    local chart_version="${CAMUNDA_HELM_CHART_VERSION:-}"

    log "Installing Camunda with Bitnami sub-charts..."
    local helm_args=(
        --namespace "${NAMESPACE}"
        --values "${VALUES_FILE}"
        --timeout 20m
        --wait
    )
    local chart_ref="camunda/camunda-platform"
    if [[ -n "${chart_version}" ]]; then
        log "  Using chart version: ${chart_version}"
        helm_args+=(--version "${chart_version}")
        if [[ "${chart_version}" == *snapshot* ]]; then
            log "  Using OCI registry for snapshot version"
            chart_ref="oci://ghcr.io/camunda/helm/camunda-platform"
        fi
    fi

    helm upgrade --install "${RELEASE_NAME}" "${chart_ref}" "${helm_args[@]}"

    log "Helm install complete. Waiting for rollouts..."
    kubectl rollout status statefulset/camunda-zeebe -n "${NAMESPACE}" --timeout=600s || true
    kubectl rollout status deployment/camunda-identity -n "${NAMESPACE}" --timeout=300s || true
    kubectl rollout status deployment/camunda-connectors -n "${NAMESPACE}" --timeout=300s || true

    log "Deployment ready."
    kubectl get pods -n "${NAMESPACE}"
}

run_seed_job() {
    log "Cleaning up previous seed job (if any)..."
    kubectl delete job seed-test-data -n "${NAMESPACE}" --ignore-not-found=true

    log "Applying seed job..."
    kubectl apply -n "${NAMESPACE}" -f "${SEED_JOB}"

    log "Following seed job logs..."
    # Wait for pod to be created, then tail logs
    local pod=""
    for _i in $(seq 1 30); do
        pod=$(kubectl get pods -n "${NAMESPACE}" -l job-name=seed-test-data \
            --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$pod" ]]; then break; fi
        sleep 2
    done

    if [[ -z "$pod" ]]; then
        err "Could not find seed job pod"
        return 1
    fi

    log "Seed pod: ${pod}"

    # Stream logs in background and wait for completion
    kubectl logs -f -n "${NAMESPACE}" "${pod}" -c seed &
    local logs_pid=$!

    if kubectl wait --for=condition=complete job/seed-test-data \
        -n "${NAMESPACE}" --timeout=900s; then
        log "Seed job COMPLETED successfully"
        kill $logs_pid 2>/dev/null || true
        wait $logs_pid 2>/dev/null || true
        return 0
    else
        kill $logs_pid 2>/dev/null || true
        wait $logs_pid 2>/dev/null || true
        err "Seed job FAILED or timed out"
        log "Pod status:"
        kubectl describe pod "${pod}" -n "${NAMESPACE}" | tail -20
        return 1
    fi
}

run_benchmark_job() {
    log "Cleaning up previous benchmark job (if any)..."
    kubectl delete job migration-benchmark -n "${NAMESPACE}" --ignore-not-found=true

    log "Applying benchmark job..."
    kubectl apply -n "${NAMESPACE}" -f "${BENCHMARK_JOB}"

    log "Waiting for benchmark to run (5 min deadline)..."
    # The benchmark runs indefinitely; activeDeadlineSeconds (300s) terminates it.
    # DeadlineExceeded counts as a failure condition, so we wait for that.
    if kubectl wait --for=condition=complete job/migration-benchmark \
        -n "${NAMESPACE}" --timeout=600s 2>/dev/null; then
        log "Benchmark job completed"
    elif kubectl wait --for=condition=failed job/migration-benchmark \
        -n "${NAMESPACE}" --timeout=600s 2>/dev/null; then
        log "Benchmark job terminated (DeadlineExceeded — expected)"
    else
        err "Benchmark job did not finish within timeout"
        return 1
    fi

    kubectl logs job/migration-benchmark -n "${NAMESPACE}" --tail=20 || true

    # Wait for ES to index the benchmark data
    log "Waiting 30s for Elasticsearch to index benchmark data..."
    sleep 30
}

run_verify_job() {
    log "Cleaning up previous verify job (if any)..."
    kubectl delete job verify-test-data -n "${NAMESPACE}" --ignore-not-found=true

    log "Applying verify job..."
    # verify-test-data-job.yml uses ${NAMESPACE} placeholder — substitute it
    sed "s/\${NAMESPACE}/${NAMESPACE}/g" "${VERIFY_JOB}" \
        | kubectl apply -n "${NAMESPACE}" -f -

    log "Waiting for verify job..."
    if kubectl wait --for=condition=complete job/verify-test-data \
        -n "${NAMESPACE}" --timeout=300s; then
        log "Verify job PASSED"
    else
        err "Verify job FAILED"
        kubectl logs job/verify-test-data -n "${NAMESPACE}" --tail=50 || true
        return 1
    fi

    kubectl logs job/verify-test-data -n "${NAMESPACE}" --tail=50
}

debug_services() {
    log "=== Debug: service connectivity from inside cluster ==="
    kubectl run debug-curl --rm -i --restart=Never -n "${NAMESPACE}" \
        --image=alpine/curl:latest -- sh -c '
        echo "--- Zeebe management API (9600) ---"
        curl -sf http://camunda-zeebe-gateway:9600/actuator/health/liveness && echo " => OK" || echo " => FAIL"

        echo "--- Zeebe readiness (9600) ---"
        curl -sf http://camunda-zeebe-gateway:9600/actuator/health/readiness && echo " => OK" || echo " => FAIL"

        echo "--- Zeebe REST topology (8080, no auth) ---"
        curl -s -o /dev/null -w "HTTP %{http_code}" http://camunda-zeebe-gateway:8080/v2/topology && echo ""

        echo "--- Zeebe REST topology (8080, basic auth demo:demo) ---"
        curl -sf -u demo:demo http://camunda-zeebe-gateway:8080/v2/topology | head -c 200 && echo " => OK" || echo " => FAIL"

        echo "--- Keycloak OIDC discovery ---"
        curl -sf http://camunda-keycloak:80/auth/realms/camunda-platform/.well-known/openid-configuration | head -c 200 && echo " => OK" || echo " => FAIL"

        echo "--- WebModeler readiness ---"
        curl -sf http://camunda-web-modeler-restapi:8091/health/readiness && echo " => OK" || echo " => FAIL (expected if WM not deployed)"
    ' 2>/dev/null || true
}

teardown() {
    log "Deleting Kind cluster '${CLUSTER_NAME}'..."
    kind delete cluster --name "${CLUSTER_NAME}"
    log "Cluster deleted."
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    local cmd="${1:-full}"

    case "$cmd" in
        full)
            ensure_cluster
            create_pull_secrets
            create_identity_secrets
            deploy_camunda
            debug_services
            run_seed_job
            run_benchmark_job
            run_verify_job
            ;;
        deploy-only)
            ensure_cluster
            create_pull_secrets
            create_identity_secrets
            deploy_camunda
            ;;
        seed-only)
            kubectl config use-context "kind-${CLUSTER_NAME}"
            debug_services
            run_seed_job
            run_benchmark_job
            ;;
        verify-only)
            kubectl config use-context "kind-${CLUSTER_NAME}"
            run_verify_job
            ;;
        debug)
            kubectl config use-context "kind-${CLUSTER_NAME}"
            debug_services
            ;;
        teardown)
            teardown
            ;;
        *)
            echo "Usage: $0 {full|deploy-only|seed-only|verify-only|debug|teardown}"
            exit 1
            ;;
    esac
}

main "$@"

#!/bin/bash

# Wait until the Camunda OIDC issuer (Keycloak realm) is reachable, then restart
# the application workloads so they recover immediately instead of waiting out
# Kubernetes CrashLoopBackOff.
#
# Why this exists: in domain + OIDC mode the Camunda app pods (Zeebe/orchestration
# and Connectors) fetch the OIDC discovery document from the public Keycloak issuer
# at startup. That URL only answers once (a) the Identity component has provisioned
# the `camunda-platform` realm and (b) the public route converges (DNS + TLS
# certificate + ingress). Until then the pods crash-loop, and Kubernetes backoff can
# delay the next restart by several minutes, so a first deployment can look broken
# for a while. This script waits (up to a timeout) for the discovery endpoint to
# return HTTP 200, then rolls the app workloads so they restart cleanly.
#
# It is safe to run right after the Helm install, and it FAILS OPEN: if the issuer
# never answers within the timeout it warns and exits 0, so it never blocks a deploy.
# The hard readiness gate is check-deployment-ready.sh, which runs afterwards.
#
# The realm is created by the Identity component, so a permanently missing issuer is
# almost always a broken Identity rather than a slow one. Restarting Zeebe/Connectors
# cannot help in that case, so on timeout this script reports the Identity workload
# state (restarts, CrashLoopBackOff, OOMKilled, exit codes) instead of just warning
# that Keycloak was slow.
#
# Configuration (all optional, sensible defaults):
#   CAMUNDA_NAMESPACE              namespace Camunda is installed in (default: camunda)
#   CAMUNDA_RELEASE_NAME          Helm release name (default: camunda)
#   CAMUNDA_DOMAIN                public host serving Keycloak (default: camunda.example.com)
#   CAMUNDA_OIDC_ISSUER_URL       full issuer base URL; overrides the one built from CAMUNDA_DOMAIN
#   KEYCLOAK_WAIT_TIMEOUT_SECONDS total wall-clock budget in seconds (default: 600)
#   KEYCLOAK_WAIT_INSECURE        'true' to skip TLS verification (e.g. an untrusted internal CA)
#   KEYCLOAK_WAIT_SKIP_RESTART    'true' to only wait for the issuer and not restart the workloads

set -uo pipefail

namespace="${CAMUNDA_NAMESPACE:-camunda}"
release="${CAMUNDA_RELEASE_NAME:-camunda}"
domain="${CAMUNDA_DOMAIN:-camunda.example.com}"
issuer="${CAMUNDA_OIDC_ISSUER_URL:-https://${domain}/auth/realms/camunda-platform}"
discovery="${issuer%/}/.well-known/openid-configuration"
timeout_seconds="${KEYCLOAK_WAIT_TIMEOUT_SECONDS:-600}"
identity_deployment="${release}-identity"

curl_opts=(--silent --output /dev/null --max-time 5)
if [ "${KEYCLOAK_WAIT_INSECURE:-false}" = "true" ]; then
    curl_opts+=(--insecure)
fi

warn() {
    # Non-fatal warning; this script is fail-open and never aborts a deploy.
    printf 'WARNING: %s\n' "$1"
}

# Ready replica count of the Identity deployment. Prints the count and returns 0
# when the deployment exists, returns 1 when it does not (Identity disabled, or a
# release name mismatch). `.status.readyReplicas` is absent - not 0 - while no
# replica is ready, hence the explicit default.
identity_ready_replicas() {
    local out
    out="$(kubectl --namespace "$namespace" get deployment "$identity_deployment" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" || return 1
    printf '%s' "${out:-0}"
}

# Names of the pods backing the Identity deployment, resolved through the
# deployment's own label selector.
#
# Matching on the pod name prefix would be wrong: the chart can deploy siblings
# whose names also start with `<release>-identity-`, such as the bundled
# `identityKeycloak` and its PostgreSQL. Reporting their container states as
# Identity's would point the reader at the wrong component. `go-template` is
# built into kubectl, so resolving the selector adds no dependency.
identity_pods() {
    local selector
    # SC2016: `$k` and `$v` are Go template variables consumed by kubectl, they
    # must reach it literally and must not be expanded by the shell.
    # shellcheck disable=SC2016
    selector="$(kubectl --namespace "$namespace" get deployment "$identity_deployment" \
        -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}' 2>/dev/null)" || return 0
    selector="${selector%,}"
    [ -n "$selector" ] || return 0
    kubectl --namespace "$namespace" get pods --selector "$selector" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null
}

# Per-container state of every Identity pod: restarts, why it is waiting, and how
# the previous attempt died. 'OOMKilled' or a non-zero exit code here is the root
# cause of a platform-wide OIDC failure, not Keycloak being slow.
#
# Init containers are reported too. In domain mode Identity runs an `import-ca-cert`
# init container, and a pod stuck in `Init:CrashLoopBackOff` has an empty
# `containerStatuses`, so looking only at the regular containers would report the
# pod as missing and hide the real failure.
identity_container_states() {
    local pod
    for pod in $(identity_pods); do
        kubectl --namespace "$namespace" get pod "$pod" -o jsonpath="{range .status.initContainerStatuses[*]}${pod}/{.name} (init) restarts={.restartCount} waiting={.state.waiting.reason} lastTerminated={.lastState.terminated.reason} exitCode={.lastState.terminated.exitCode}{'\n'}{end}{range .status.containerStatuses[*]}${pod}/{.name} restarts={.restartCount} waiting={.state.waiting.reason} lastTerminated={.lastState.terminated.reason} exitCode={.lastState.terminated.exitCode}{'\n'}{end}" 2>/dev/null
    done
}

# Loud, actionable report explaining that Identity - not Keycloak - is the blocker.
report_identity() {
    local ready states
    if ! ready="$(identity_ready_replicas)"; then
        echo "Identity deployment '${identity_deployment}' not found in namespace '${namespace}'."
        echo "If Identity is disabled, the 'camunda-platform' realm must be provisioned another way."
        return 0
    fi
    if [ "$ready" -ge 1 ]; then
        echo "Identity deployment '${identity_deployment}' reports ${ready} ready replica(s);"
        echo "the issuer is likely still converging (DNS, TLS certificate or ingress)."
        return 0
    fi

    echo "ROOT CAUSE: the 'camunda-platform' realm is created by the Identity component,"
    echo "and '${identity_deployment}' has no ready replica. Until Identity starts, the issuer"
    echo "${issuer} cannot exist, and every other component will keep failing OIDC discovery"
    echo "with HTTP 404/503. Restarting Zeebe or Connectors cannot fix this."
    echo ""
    echo "Identity container states:"
    states="$(identity_container_states)"
    if [ -n "$states" ]; then
        printf '%s\n' "$states"
    else
        echo "  (no Identity pod found)"
    fi
    echo ""
    echo "Next steps:"
    echo "  kubectl --namespace ${namespace} describe deployment ${identity_deployment}"
    echo "  kubectl --namespace ${namespace} logs deployment/${identity_deployment} --all-containers --previous"
    echo "A 'lastTerminated=OOMKilled' above means Identity needs a higher memory limit."
}

# Require a plain positive integer; fall back otherwise. The digits-only check
# rejects signs/letters before the 10# normalization (which also stops a leading
# zero from being read as octal in the arithmetic below).
raw_timeout="$timeout_seconds"
case "$timeout_seconds" in
    '' | *[!0-9]*) timeout_seconds=0 ;;
esac
timeout_seconds=$((10#$timeout_seconds))
if [ "$timeout_seconds" -lt 1 ]; then
    warn "KEYCLOAK_WAIT_TIMEOUT_SECONDS='${raw_timeout}' is not a positive integer; using 600."
    timeout_seconds=600
fi

# Fail open immediately if a required tool is missing, instead of spinning until
# the deadline.
for required in curl kubectl; do
    if ! command -v "$required" >/dev/null 2>&1; then
        warn "'$required' is not available; skipping the Keycloak readiness wait."
        exit 0
    fi
done

echo "Waiting for the Keycloak OIDC discovery document (up to ${timeout_seconds}s): ${discovery}"
deadline=$(($(date +%s) + timeout_seconds))
attempt=0
identity_warned=false
while [ "$(date +%s)" -lt "$deadline" ]; do
    attempt=$((attempt + 1))
    code=$(curl "${curl_opts[@]}" -w '%{http_code}' "$discovery" || true)
    code="${code:-000}"
    if [ "$code" = "200" ]; then
        echo "Keycloak issuer is reachable (HTTP ${code}) after ${attempt} attempt(s)."
        if [ "${KEYCLOAK_WAIT_SKIP_RESTART:-false}" = "true" ]; then
            echo "KEYCLOAK_WAIT_SKIP_RESTART=true; leaving the workload restart to the caller."
            exit 0
        fi
        echo "Restarting Camunda workloads to clear any first-start crash-loop backoff..."
        kubectl --namespace "$namespace" rollout restart "statefulset/${release}-zeebe" || true
        # Connectors may be disabled in some scenarios; tolerate that specific case
        # (NotFound) but surface any other error instead of silently swallowing it.
        if connectors_out=$(kubectl --namespace "$namespace" rollout restart "deployment/${release}-connectors" 2>&1); then
            printf '%s\n' "$connectors_out"
        else
            case "$connectors_out" in
                *NotFound*) echo "Connectors deployment not present; skipping its restart." ;;
                *) printf '%s\n' "$connectors_out" >&2 ;;
            esac
        fi
        exit 0
    fi
    echo "[attempt ${attempt}] not ready yet (HTTP ${code}); retrying in 5s..."
    # Surface a crash-looping Identity early (once) instead of letting the user
    # stare at identical retry lines for the whole budget.
    if [ "$identity_warned" = "false" ] && [ $((attempt % 12)) -eq 0 ]; then
        case "$(identity_container_states)" in
            *waiting=CrashLoopBackOff* | *lastTerminated=OOMKilled*)
                identity_warned=true
                warn "Identity is not starting; it is what provisions the OIDC realm at ${issuer}."
                report_identity
                ;;
        esac
    fi
    sleep 5
done

warn "Keycloak issuer ${discovery} did not return 200 within ${timeout_seconds}s; continuing anyway."
report_identity
exit 0

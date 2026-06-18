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
#
# Configuration (all optional, sensible defaults):
#   CAMUNDA_NAMESPACE              namespace Camunda is installed in (default: camunda)
#   CAMUNDA_RELEASE_NAME          Helm release name (default: camunda)
#   CAMUNDA_DOMAIN                public host serving Keycloak (default: camunda.example.com)
#   CAMUNDA_OIDC_ISSUER_URL       full issuer base URL; overrides the one built from CAMUNDA_DOMAIN
#   KEYCLOAK_WAIT_TIMEOUT_SECONDS total wall-clock budget in seconds (default: 600)
#   KEYCLOAK_WAIT_INSECURE        'true' to skip TLS verification (e.g. an untrusted internal CA)

set -uo pipefail

namespace="${CAMUNDA_NAMESPACE:-camunda}"
release="${CAMUNDA_RELEASE_NAME:-camunda}"
domain="${CAMUNDA_DOMAIN:-camunda.example.com}"
issuer="${CAMUNDA_OIDC_ISSUER_URL:-https://${domain}/auth/realms/camunda-platform}"
discovery="${issuer%/}/.well-known/openid-configuration"
timeout_seconds="${KEYCLOAK_WAIT_TIMEOUT_SECONDS:-600}"

curl_opts=(--silent --output /dev/null --max-time 5)
if [ "${KEYCLOAK_WAIT_INSECURE:-false}" = "true" ]; then
    curl_opts+=(--insecure)
fi

warn() {
    # Non-fatal warning; this script is fail-open and never aborts a deploy.
    printf 'WARNING: %s\n' "$1"
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
while [ "$(date +%s)" -lt "$deadline" ]; do
    attempt=$((attempt + 1))
    code=$(curl "${curl_opts[@]}" -w '%{http_code}' "$discovery" || true)
    code="${code:-000}"
    if [ "$code" = "200" ]; then
        echo "Keycloak issuer is reachable (HTTP ${code}) after ${attempt} attempt(s)."
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
    sleep 5
done

warn "Keycloak issuer ${discovery} did not return 200 within ${timeout_seconds}s; continuing anyway."
exit 0

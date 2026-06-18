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
# for a while. This script blocks until the discovery endpoint returns HTTP 200,
# then rolls the app workloads so they restart cleanly.
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
    # Surface as a GitHub Actions annotation in CI, plain text otherwise.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::warning::$1"
    else
        echo "WARNING: $1"
    fi
}

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
        # Connectors may be disabled in some scenarios; only restart it when present,
        # and keep its errors visible (do not blanket-silence stderr).
        if kubectl --namespace "$namespace" get "deployment/${release}-connectors" >/dev/null 2>&1; then
            kubectl --namespace "$namespace" rollout restart "deployment/${release}-connectors" || true
        fi
        exit 0
    fi
    echo "[attempt ${attempt}] not ready yet (HTTP ${code}); retrying in 5s..."
    sleep 5
done

warn "Keycloak issuer ${discovery} did not return 200 within ${timeout_seconds}s; continuing anyway."
exit 0

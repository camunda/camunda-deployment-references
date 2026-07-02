#!/bin/bash
# check-keycloak-h2c.sh
#
# Regression probe for the HTTP/2 cleartext (h2c) crash of the camunda/keycloak
# quay-optimized images (see issue #2809 and camunda/keycloak#596).
#
# A previously-affected image copied the AWS JDBC wrapper's transitive dependencies
# into /opt/keycloak/providers, including an older Netty that shadowed Keycloak's
# bundled, Vert.x-aligned Netty; an h2c upgrade then threw NoSuchMethodError and
# terminated the Keycloak process. The fix ships in the image itself (the conflicting
# Netty is removed from providers, camunda/keycloak#596); this probe fails if that
# regresses.
#
# It port-forwards the Keycloak service, sends an h2c upgrade with `curl --http2`,
# and asserts a valid HTTP response comes back (i.e. the process did not crash).

set -euo pipefail

CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
KEYCLOAK_SERVICE=${KEYCLOAK_SERVICE:-keycloak-service}
# Derived from the Service object once Keycloak is up (see below), unless overridden here.
KEYCLOAK_HTTP_PORT=${KEYCLOAK_HTTP_PORT:-}
LOCAL_PORT=${LOCAL_PORT:-18080}
PROBE_PATH=${PROBE_PATH:-/auth/realms/master}

# Fail fast (and clearly) if this runner's curl cannot negotiate HTTP/2 — otherwise
# `curl --http2` would error and be misreported below as an H2C regression.
if ! curl -V | grep -qiw HTTP2; then
    echo "❌ curl on this runner was built without HTTP/2 support; cannot run the h2c probe."
    exit 1
fi

# Keycloak is already deployed and waited on by keycloak/deploy.sh before this runs,
# so this is a short defensive re-check rather than a long provisioning wait.
echo "Waiting for Keycloak to be Ready..."
kubectl wait --for=condition=Ready --timeout=120s keycloak --all -n "$CAMUNDA_NAMESPACE"

# Derive the Keycloak service HTTP port from the Service object rather than hard-coding it
# (the no-domain CR leaves httpPort unset, so Keycloak serves on its default 8080). Prefer
# the port named "http", else the first port, else fall back to 8080.
if [ -z "$KEYCLOAK_HTTP_PORT" ]; then
    KEYCLOAK_HTTP_PORT=$(kubectl get "svc/${KEYCLOAK_SERVICE}" -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null || true)
fi
if [ -z "$KEYCLOAK_HTTP_PORT" ]; then
    KEYCLOAK_HTTP_PORT=$(kubectl get "svc/${KEYCLOAK_SERVICE}" -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
fi
KEYCLOAK_HTTP_PORT=${KEYCLOAK_HTTP_PORT:-8080}

echo "Port-forwarding svc/${KEYCLOAK_SERVICE} ${LOCAL_PORT}:${KEYCLOAK_HTTP_PORT} (namespace ${CAMUNDA_NAMESPACE})..."
kubectl port-forward -n "$CAMUNDA_NAMESPACE" "svc/${KEYCLOAK_SERVICE}" "${LOCAL_PORT}:${KEYCLOAK_HTTP_PORT}" >/dev/null 2>&1 &
pf_pid=$!
cleanup() { kill "$pf_pid" 2>/dev/null || true; }
trap cleanup EXIT

url="http://localhost:${LOCAL_PORT}${PROBE_PATH}"

# Wait until the tunnel accepts plain HTTP/1.1 traffic before probing h2c.
ready=false
for _ in $(seq 1 30); do
    if ! kill -0 "$pf_pid" 2>/dev/null; then
        echo "❌ kubectl port-forward exited early (service missing, or local port ${LOCAL_PORT} already in use); aborting probe."
        exit 1
    fi
    if curl -sS -o /dev/null --max-time 5 "$url" 2>/dev/null; then
        ready=true
        break
    fi
    sleep 2
done
if [ "$ready" != "true" ]; then
    echo "❌ Could not reach Keycloak over HTTP/1.1 through the port-forward; aborting probe."
    kubectl get pods -n "$CAMUNDA_NAMESPACE" -o wide || true
    exit 1
fi

echo "Sending an HTTP/2 cleartext (h2c) upgrade request to ${url}..."
curl_rc=0
metrics=$(curl -sS -o /dev/null -w '%{http_code} %{http_version}' --http2 --max-time 20 "$url") || curl_rc=$?
http_code=${metrics%% *}
http_version=${metrics##* }
echo "curl exit=${curl_rc} http_code=${http_code:-} http_version=${http_version:-}"

if [ "$curl_rc" -ne 0 ] || [ -z "$http_code" ] || [ "$http_code" = "000" ]; then
    echo "❌ H2C regression: Keycloak dropped the HTTP/2 cleartext connection (NoSuchMethodError crash)."
    echo "   Fix: use a camunda/keycloak image whose /opt/keycloak/providers has no conflicting Netty (camunda/keycloak#596)."
    echo "   Or, on an older image without that fix, set QUARKUS_HTTP_HTTP2=false on the Keycloak CR to force HTTP/1.1."
    kubectl get pods -n "$CAMUNDA_NAMESPACE" -o wide || true
    exit 1
fi

# The request must actually negotiate HTTP/2, otherwise the h2c upgrade path (the one that
# used to crash) was never exercised and this probe would pass without guarding anything.
case "${http_version:-}" in
    2 | 2.0) : ;;
    *)
        echo "❌ H2C probe ineffective: the request negotiated HTTP/${http_version:-unknown}, not HTTP/2."
        echo "   The h2c upgrade path was not exercised. Ensure HTTP/2 is enabled on Keycloak"
        echo "   (do not set QUARKUS_HTTP_HTTP2=false on the pinned, Netty-fixed image)."
        kubectl get pods -n "$CAMUNDA_NAMESPACE" -o wide || true
        exit 1
        ;;
esac

# An h2c crash exits the JVM (pod restart); make sure Keycloak is still up.
if ! kubectl wait --for=condition=Ready --timeout=60s keycloak --all -n "$CAMUNDA_NAMESPACE"; then
    echo "❌ Keycloak is not Ready after the H2C probe — it likely crashed on the h2c request."
    kubectl get pods -n "$CAMUNDA_NAMESPACE" -o wide || true
    exit 1
fi

echo "✅ H2C probe passed: Keycloak responded to the h2c request without dropping the connection (http_code=${http_code}) and stayed Ready."

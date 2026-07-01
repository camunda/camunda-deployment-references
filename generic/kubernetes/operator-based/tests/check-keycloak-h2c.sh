#!/bin/bash
# check-keycloak-h2c.sh
#
# Regression probe for the HTTP/2 cleartext (h2c) crash of the camunda/keycloak
# quay-optimized images (see issue #2809 and camunda/keycloak#596).
#
# The image build copies the AWS JDBC wrapper's transitive dependencies into
# /opt/keycloak/providers, which includes an older Netty (netty-nio-client) that
# shadows Keycloak's bundled, Vert.x-aligned Netty. On an affected image an h2c
# upgrade throws NoSuchMethodError and terminates the Keycloak process (the
# connection is dropped). The no-domain Keycloak CR disables HTTP/2
# (QUARKUS_HTTP_HTTP2=false) to avoid this; this probe fails if that protection
# regresses.
#
# It port-forwards the Keycloak service, sends an h2c upgrade with `curl --http2`,
# and asserts a valid HTTP response comes back (i.e. the process did not crash).

set -euo pipefail

CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
KEYCLOAK_SERVICE=${KEYCLOAK_SERVICE:-keycloak-service}
KEYCLOAK_HTTP_PORT=${KEYCLOAK_HTTP_PORT:-18080}
LOCAL_PORT=${LOCAL_PORT:-18080}
PROBE_PATH=${PROBE_PATH:-/auth/realms/master}

echo "Waiting for Keycloak to be Ready..."
kubectl wait --for=condition=Ready --timeout=300s keycloak --all -n "$CAMUNDA_NAMESPACE"

echo "Port-forwarding svc/${KEYCLOAK_SERVICE} ${LOCAL_PORT}:${KEYCLOAK_HTTP_PORT} (namespace ${CAMUNDA_NAMESPACE})..."
kubectl port-forward -n "$CAMUNDA_NAMESPACE" "svc/${KEYCLOAK_SERVICE}" "${LOCAL_PORT}:${KEYCLOAK_HTTP_PORT}" >/dev/null 2>&1 &
pf_pid=$!
cleanup() { kill "$pf_pid" 2>/dev/null || true; }
trap cleanup EXIT

url="http://localhost:${LOCAL_PORT}${PROBE_PATH}"

# Wait until the tunnel accepts plain HTTP/1.1 traffic before probing h2c.
ready=false
for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
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
http_code=$(curl -sS -o /dev/null -w '%{http_code}' --http2 --max-time 20 "$url") || curl_rc=$?
echo "curl exit=${curl_rc} http_code=${http_code}"

if [ "$curl_rc" -ne 0 ] || [ -z "$http_code" ] || [ "$http_code" = "000" ]; then
    echo "❌ H2C regression: Keycloak dropped the HTTP/2 cleartext connection (NoSuchMethodError crash)."
    echo "   Keep QUARKUS_HTTP_HTTP2=false on the no-domain Keycloak CR, or use a Netty-aligned image (camunda/keycloak#596)."
    kubectl get pods -n "$CAMUNDA_NAMESPACE" -o wide || true
    exit 1
fi

# An h2c crash exits the JVM (pod restart); make sure Keycloak is still up.
if ! kubectl wait --for=condition=Ready --timeout=90s keycloak --all -n "$CAMUNDA_NAMESPACE"; then
    echo "❌ Keycloak is not Ready after the H2C probe — it likely crashed on the h2c request."
    kubectl get pods -n "$CAMUNDA_NAMESPACE" -o wide || true
    exit 1
fi

echo "✅ H2C probe passed: Keycloak answered the h2c upgrade (http_code=${http_code}) and stayed Ready."

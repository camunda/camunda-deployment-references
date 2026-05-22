#!/bin/bash

echo "🔄 Starting port-forward..."
kubectl --context "$CLUSTER_1_NAME" -n "$CAMUNDA_NAMESPACE_1" port-forward "services/$CAMUNDA_RELEASE_NAME-zeebe-gateway" 8080:8080 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Cleanup on exit
cleanup() {
  echo "🛑 Stopping port-forward (PID: $PORT_FORWARD_PID)..."
  kill "$PORT_FORWARD_PID" 2>/dev/null || echo "⚠️ Failed to kill PID $PORT_FORWARD_PID"
}
trap cleanup EXIT

# Wait a bit to ensure port-forward is ready
sleep 2

echo "📡 Fetching Zeebe cluster topology..."
# Only attach basic-auth when both vars are set. Never default to demo:demo
# (see INC-5340) — an unauthenticated cluster works without -u, an
# authenticated one must receive real credentials from the caller.
AUTH_ARGS=()
if [[ -n "${ZEEBE_BASIC_AUTH_USER:-}" && -n "${ZEEBE_BASIC_AUTH_PASSWORD:-}" ]]; then
    AUTH_ARGS=(-u "${ZEEBE_BASIC_AUTH_USER}:${ZEEBE_BASIC_AUTH_PASSWORD}")
fi
topology=$(curl -s -L "${AUTH_ARGS[@]}" -X GET 'http://localhost:8080/v2/topology' -H 'Accept: application/json')
echo "$topology" > zeebe-topology.json

jq . zeebe-topology.json

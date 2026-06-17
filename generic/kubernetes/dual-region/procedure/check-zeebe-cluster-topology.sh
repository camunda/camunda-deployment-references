#!/bin/bash

echo "🔄 Starting port-forward..."
kubectl --context "$CLUSTER_1_NAME" -n "$CAMUNDA_NAMESPACE_1" port-forward "services/$CAMUNDA_RELEASE_NAME-zeebe-gateway" 8080:8080 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Cleanup on exit
cleanup() {
  echo "🛑 Stopping port-forward (PID: $PORT_FORWARD_PID)..."
  kill $PORT_FORWARD_PID
}
trap cleanup EXIT

# Wait a bit to ensure port-forward is ready
sleep 2

echo "📡 Fetching Zeebe cluster topology..."
if ! topology=$(curl -s --show-error --fail -L -X GET 'http://localhost:8080/v2/topology' -H 'Accept: application/json'); then
  echo "❌ Failed to fetch topology from /v2/topology (HTTP error or connection failure)." >&2
  exit 1
fi
echo "$topology" > zeebe-topology.json

jq . zeebe-topology.json

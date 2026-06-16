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
# Camunda 8.8+ enforces authentication on the REST API (/v2/topology). In CI the
# gateway is protected by a Vault-provisioned admin exported to the job
# environment as CAMUNDA_BASIC_AUTH_USER/PASSWORD (see internal-camunda-ci-credentials),
# so prefer those credentials; fall back to ZEEBE_BASIC_AUTH_* and finally the
# chart demo:demo default for unprotected/local deployments.
auth_user="${CAMUNDA_BASIC_AUTH_USER:-${ZEEBE_BASIC_AUTH_USER:-demo}}"
auth_password="${CAMUNDA_BASIC_AUTH_PASSWORD:-${ZEEBE_BASIC_AUTH_PASSWORD:-demo}}"
topology=$(curl -s --show-error --fail -L -u "${auth_user}:${auth_password}" -X GET 'http://localhost:8080/v2/topology' -H 'Accept: application/json')
echo "$topology" > zeebe-topology.json

jq . zeebe-topology.json

#!/bin/bash

echo "🔄 Starting port-forward..."
kubectl --context "$CLUSTER_1_NAME" -n "$CAMUNDA_NAMESPACE_1" port-forward "services/$CAMUNDA_RELEASE_NAME-zeebe-gateway" 8080:8080 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Cleanup on exit
cleanup() {
  echo "🛑 Stopping port-forward (PID: $PORT_FORWARD_PID)..."
  kill "$PORT_FORWARD_PID" 2>/dev/null || echo "⚠️ Failed to kill PID $PORT_FORWARD_PID"
  [ -n "${curl_cfg:-}" ] && rm -f "$curl_cfg"
}
trap cleanup EXIT

# Wait a bit to ensure port-forward is ready
sleep 2

echo "📡 Fetching Zeebe cluster topology..."
# Camunda 8.8+ enforces authentication on the REST API (/v2/topology). In CI the
# gateway is protected by a Vault-provisioned admin exported to the job environment
# as CAMUNDA_BASIC_AUTH_USER/PASSWORD (see internal-camunda-ci-credentials). Select a
# COMPLETE credential pair from a single source (never mix user/password across
# sources): prefer CAMUNDA_*, then ZEEBE_*, then the chart demo:demo default for
# unprotected/local deployments.
if [ -n "${CAMUNDA_BASIC_AUTH_USER:-}" ] && [ -n "${CAMUNDA_BASIC_AUTH_PASSWORD:-}" ]; then
  auth_user="$CAMUNDA_BASIC_AUTH_USER"; auth_password="$CAMUNDA_BASIC_AUTH_PASSWORD"
elif [ -n "${ZEEBE_BASIC_AUTH_USER:-}" ] && [ -n "${ZEEBE_BASIC_AUTH_PASSWORD:-}" ]; then
  auth_user="$ZEEBE_BASIC_AUTH_USER"; auth_password="$ZEEBE_BASIC_AUTH_PASSWORD"
else
  auth_user="demo"; auth_password="demo"
fi

# Under CI a missing credential pair is a configuration error: refuse to silently
# fall back to demo:demo, which would mask a missing Vault-provisioned secret
# (consistent with the repo's INC-5340 hardening).
if [ "${CI:-}" = "true" ] && [ "$auth_user" = "demo" ]; then
  echo "ERROR: no CAMUNDA_BASIC_AUTH_* / ZEEBE_BASIC_AUTH_* credentials provided under CI; refusing to fall back to demo:demo." >&2
  exit 1
fi

# Pass the (Vault-provisioned) credentials to curl via a 0600 config file removed on
# exit, instead of `-u user:password`, so the password is never exposed on the curl
# command line via ps/proc on the runner.
curl_cfg="$(mktemp "${TMPDIR:-/tmp}/zeebe-topology-curl.XXXXXX")"
chmod 600 "$curl_cfg"
# Escape backslashes first, then double-quotes, so a credential containing either
# character does not break the quoted curl-config value.
esc_user=${auth_user//\\/\\\\}; esc_user=${esc_user//\"/\\\"}
esc_password=${auth_password//\\/\\\\}; esc_password=${esc_password//\"/\\\"}
printf 'user = "%s:%s"\n' "$esc_user" "$esc_password" > "$curl_cfg"
if ! topology=$(curl -s --show-error --fail -L --config "$curl_cfg" -X GET 'http://localhost:8080/v2/topology' -H 'Accept: application/json'); then
  echo "❌ Failed to fetch topology from /v2/topology (HTTP error or connection failure)." >&2
  exit 1
fi
echo "$topology" > zeebe-topology.json

jq . zeebe-topology.json

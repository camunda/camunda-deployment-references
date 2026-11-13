#!/bin/bash

# Give the Management Identity client access to the Keycloak Admin REST API.
#
# Why this exists: Keycloak 26.8.2 fixes CVE-2026-19688 by enforcing an audience
# check on the Admin REST API. A token is accepted only if it carries the built-in
# `kc-admin-api` client scope, and Keycloak assigns that scope to its own clients
# (`admin-cli`, `security-admin-console`) only. Management Identity manages the
# `camunda-platform` realm through its own `camunda-identity` client (client
# credentials), which does not get the scope, so Identity stops at startup with:
#
#   KeycloakConfiguration : Unable to connect to Keycloak at '...'. HTTP status code: 401
#
# Identity creates the realm and the client before that check fails, so this script
# waits for the client, assigns `kc-admin-api` to it as a default client scope, and
# restarts Identity. The assignment survives Identity's own client setup on later
# starts. Tracked upstream in camunda/camunda#69230; remove this step once the
# Identity release in use assigns the scope itself.
#
# Disabling the check (`--spi-admin--audience-check-enabled=false`) also works but
# turns the CVE fix off, so it is not used here.
#
# Run it right after the Helm install, before waiting for the OIDC issuer. It is
# idempotent, and it does nothing on a Keycloak without the check (no `kc-admin-api`
# scope in the realm). It FAILS OPEN: on timeout it warns and exits 0; the
# deployment readiness check that follows is the hard gate.
#
# Requires the Keycloak operator instance from this directory: the operator injects
# the bootstrap admin credentials (secret `keycloak-initial-admin`) into the Keycloak
# container as KC_BOOTSTRAP_ADMIN_USERNAME / KC_BOOTSTRAP_ADMIN_PASSWORD, so they
# never leave the pod. kcadm runs as the container user with HOME and its config
# under /tmp, which also works under the OpenShift restricted SCC (arbitrary UID).
#
# Configuration (all optional):
#   KUBECTL                              CLI to use, `kubectl` or `oc` (default: kubectl, or oc if kubectl is missing)
#   CAMUNDA_NAMESPACE                    namespace of Camunda and Keycloak (default: camunda)
#   CAMUNDA_RELEASE_NAME                 Helm release name (default: camunda)
#   IDENTITY_DEPLOYMENT                  Identity deployment (default: <CAMUNDA_RELEASE_NAME>-identity)
#   KEYCLOAK_STATEFULSET                 Keycloak statefulset, the name of the Keycloak CR (default: keycloak)
#   KEYCLOAK_POD                         Keycloak pod to run kcadm in (default: <KEYCLOAK_STATEFULSET>-0)
#   KEYCLOAK_CONTAINER                   container in that pod (default: the pod's default container)
#   KEYCLOAK_LOCAL_URL                   Keycloak URL inside the pod (default: http://localhost:<port>/auth, with the
#                                        CR's spec.http.httpPort, 8080 if unset; 18080 if the CR cannot be read)
#   KEYCLOAK_REALM                       realm Identity manages (default: camunda-platform)
#   IDENTITY_CLIENT_ID                   Identity's own client (default: camunda-identity)
#   KEYCLOAK_ADMIN_API_TIMEOUT_SECONDS   total wall-clock budget in seconds (default: 600)
#   KEYCLOAK_ADMIN_SECRET                secret (keys username, password) to log in with instead of the pod's
#                                        bootstrap env; needed when the master realm no longer has that user,
#                                        e.g. after the Bitnami migration restores the Keycloak database.
#                                        The credentials go to kcadm over stdin, never on a command line.

set -uo pipefail

if [ -z "${KUBECTL:-}" ]; then
    if command -v kubectl >/dev/null 2>&1; then KUBECTL=kubectl; else KUBECTL=oc; fi
fi
namespace="${CAMUNDA_NAMESPACE:-camunda}"
release="${CAMUNDA_RELEASE_NAME:-camunda}"
identity_deployment="${IDENTITY_DEPLOYMENT:-${release}-identity}"
keycloak_statefulset="${KEYCLOAK_STATEFULSET:-keycloak}"
keycloak_pod="${KEYCLOAK_POD:-${keycloak_statefulset}-0}"
keycloak_url="${KEYCLOAK_LOCAL_URL:-}"
realm="${KEYCLOAK_REALM:-camunda-platform}"
client="${IDENTITY_CLIENT_ID:-camunda-identity}"
timeout_seconds="${KEYCLOAK_ADMIN_API_TIMEOUT_SECONDS:-600}"
scope="kc-admin-api"

container_opts=()
if [ -n "${KEYCLOAK_CONTAINER:-}" ]; then
    container_opts=(--container "$KEYCLOAK_CONTAINER")
fi

# Runs inside the Keycloak container. Exit codes: 0 scope assigned now,
# 10 already assigned, 11 no such scope (Keycloak without the check),
# 12 realm or client not created yet; anything else is an error.
# The kcadm config holds an access token, so it goes to a private temp file that
# is removed on exit.
# SC2016: the script is expanded by the shell in the pod, not here.
# shellcheck disable=SC2016
in_pod_script='
set -euo pipefail
url="$1"; realm="$2"; client="$3"; scope="$4"
if [ "${5:-}" = stdin ]; then
    IFS= read -r KC_BOOTSTRAP_ADMIN_USERNAME
    IFS= read -r KC_BOOTSTRAP_ADMIN_PASSWORD
fi
config="$(mktemp /tmp/kcadm.XXXXXX)"
trap "rm -f \"$config\"" EXIT
kcadm() { /opt/keycloak/bin/kcadm.sh "$@" --config "$config"; }

kcadm config credentials --server "$url" --realm master \
    --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

client_id="$(kcadm get clients -r "$realm" -q clientId="$client" --fields id --format csv --noquotes 2>/dev/null)" || exit 12
[ -n "$client_id" ] || exit 12

# Plain bash: the Keycloak image ships no awk.
scopes="$(kcadm get client-scopes -r "$realm" --fields id,name --format csv --noquotes)"
scope_id=""
while IFS=, read -r id name; do
    if [ "$name" = "$scope" ]; then scope_id="$id"; break; fi
done <<<"$scopes"
[ -n "$scope_id" ] || exit 11

if kcadm get "clients/$client_id/default-client-scopes" -r "$realm" --fields name --format csv --noquotes | grep -qx "$scope"; then
    exit 10
fi
kcadm update "clients/$client_id/default-client-scopes/$scope_id" -r "$realm"
'

warn() {
    # Non-fatal warning; this script is fail-open and never aborts a deploy.
    printf 'WARNING: %s\n' "$1"
}

if ! command -v "$KUBECTL" >/dev/null 2>&1; then
    warn "'$KUBECTL' is not available; skipping the '${scope}' grant."
    exit 0
fi

# The Keycloak CR sets the HTTP port (18080 in this directory, the operator's 8080 when
# unset, as on older branches), so read it rather than assume it.
if [ -z "$keycloak_url" ]; then
    if http_port="$("$KUBECTL" --namespace "$namespace" get keycloaks.k8s.keycloak.org "$keycloak_statefulset" \
        -o jsonpath='{.spec.http.httpPort}' 2>/dev/null)"; then
        keycloak_url="http://localhost:${http_port:-8080}/auth"
    else
        keycloak_url="http://localhost:18080/auth"
    fi
fi

# Optional login from a secret (see KEYCLOAK_ADMIN_SECRET), fed to the pod over stdin.
admin_credentials=""
exec_opts=()
creds_mode=""
if [ -n "${KEYCLOAK_ADMIN_SECRET:-}" ]; then
    if admin_user="$("$KUBECTL" --namespace "$namespace" get secret "$KEYCLOAK_ADMIN_SECRET" -o jsonpath='{.data.username}' | base64 -d)" &&
        admin_password="$("$KUBECTL" --namespace "$namespace" get secret "$KEYCLOAK_ADMIN_SECRET" -o jsonpath='{.data.password}' | base64 -d)" &&
        [ -n "$admin_user" ] && [ -n "$admin_password" ]; then
        admin_credentials="$(printf '%s\n%s\n' "$admin_user" "$admin_password")"
        exec_opts=(--stdin)
        creds_mode=stdin
    else
        warn "could not read username/password from secret '${KEYCLOAK_ADMIN_SECRET}'; skipping the '${scope}' grant."
        exit 0
    fi
    unset admin_user admin_password
fi

case "$timeout_seconds" in
    '' | *[!0-9]*) timeout_seconds=600 ;;
esac

echo "Waiting for the '${client}' client in realm '${realm}' to grant it '${scope}' (up to ${timeout_seconds}s, pod ${namespace}/${keycloak_pod})..."
deadline=$(($(date +%s) + timeout_seconds))
attempt=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    attempt=$((attempt + 1))
    "$KUBECTL" --namespace "$namespace" exec "${exec_opts[@]}" "$keycloak_pod" "${container_opts[@]}" -- \
        env HOME=/tmp bash -c "$in_pod_script" _ "$keycloak_url" "$realm" "$client" "$scope" "$creds_mode" \
        <<<"$admin_credentials"
    rc=$?
    case "$rc" in
        0)
            echo "Assigned '${scope}' to '${client}'; restarting Identity so it starts without waiting out its backoff."
            "$KUBECTL" --namespace "$namespace" rollout restart "deployment/${identity_deployment}" ||
                warn "could not restart deployment/${identity_deployment}; it picks the scope up on its next restart."
            exit 0
            ;;
        10)
            echo "'${client}' already has '${scope}'; nothing to do."
            exit 0
            ;;
        11)
            echo "Realm '${realm}' has no '${scope}' scope: this Keycloak does not enforce the Admin API audience check; nothing to do."
            exit 0
            ;;
        12) echo "[attempt ${attempt}] '${client}' not created yet; Identity creates it on startup. Retrying in 10s..." ;;
        *) echo "[attempt ${attempt}] kcadm failed (exit code ${rc}); retrying in 10s..." ;;
    esac
    sleep 10
done

warn "'${client}' did not get '${scope}' within ${timeout_seconds}s; Identity may stop with HTTP 401 (camunda/camunda#69230)."
exit 0

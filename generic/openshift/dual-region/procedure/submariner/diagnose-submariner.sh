#!/bin/bash
# Best-effort diagnostics for the dual-region Submariner cross-cluster connection.
# Dumps Submariner's own state (gateway pods, Gateway/Endpoint CRs, connections) to
# help understand why the cross-cluster tunnel did not establish. Never fails and
# never mutates the global kube context.
set +e

# Every command is bounded: this script runs inside an `if: failure()` debug step
# with a fixed budget, and a single slow call (`subctl show all` in particular)
# would otherwise eat it and leave the later contexts and dumps uncollected.
CMD_TIMEOUT_SECONDS="${DIAGNOSE_CMD_TIMEOUT_SECONDS:-90}"
run() {
  local rc
  timeout "${CMD_TIMEOUT_SECONDS}" "$@" 2>&1
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "(timed out after ${CMD_TIMEOUT_SECONDS}s: $*)"
  fi
  # Propagate the wrapped command's status: without this the function always
  # returns 0 (the status of the `if`), which would silently mask a failure for
  # any caller that branches on it.
  return "$rc"
}

# Support both the 0-indexed (CLUSTER_0/CLUSTER_1) and 1-indexed
# (CLUSTER_1_NAME/CLUSTER_2_NAME) cluster-context naming conventions.
C0="${CLUSTER_0:-${CLUSTER_1_NAME:-}}"
C1="${CLUSTER_1:-${CLUSTER_2_NAME:-}}"

have_subctl=false
command -v subctl >/dev/null 2>&1 && have_subctl=true

for ctx in "$C0" "$C1"; do
  [ -z "$ctx" ] && continue
  echo "===== Submariner diagnostics for context: ${ctx} ====="
  if [ "$have_subctl" = true ]; then
    echo "--- subctl show all ---"
    # `--contexts` matches the repo's verify-subctl.sh (the working Submariner check).
    run subctl show all --contexts "$ctx"
  fi
  echo "--- submariner-operator pods ---"
  run oc --context "$ctx" -n submariner-operator get pods -o wide
  echo "--- submariner-gateway logs (last 200 lines) ---"
  run oc --context "$ctx" -n submariner-operator logs -l app=submariner-gateway --tail=200 --prefix
  echo "--- Gateway / Endpoint CRs ---"
  run oc --context "$ctx" get gateways.submariner.io,endpoints.submariner.io -A -o wide
  echo "--- gateway-labelled nodes ---"
  run oc --context "$ctx" get nodes -l submariner.io/gateway=true -o wide
done

if [ -n "$C0" ]; then
  echo "===== ManagedClusterAddons (hub) ====="
  run oc --context "$C0" get managedclusteraddon -A
  # `-o wide` omits the status conditions; dump YAML so the addon conditions
  # (which explain *why* an addon is Degraded / not Available) are captured.
  echo "--- ManagedClusterAddon conditions ---"
  run oc --context "$C0" get managedclusteraddon -A -o yaml
fi

# Best-effort diagnostics: never fail the `if: failure()` debug step that runs this.
exit 0

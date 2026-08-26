#!/bin/bash
# Best-effort diagnostics for the dual-region Submariner cross-cluster connection.
# Dumps Submariner's own state (gateway pods, Gateway/Endpoint CRs, connections) to
# help understand why the cross-cluster tunnel did not establish. Never fails and
# never mutates the global kube context.
set +e

# Every command is bounded, and so is the script as a whole: it runs inside an
# `if: failure()` debug step with a fixed budget, shared with the DNS/TCP probes
# that follow it. Bounding only each command is not enough — two contexts times
# half a dozen calls would still overrun the step and swallow both the later
# dumps and the probes. Each call is therefore capped to whichever is smaller,
# the per-command timeout or what is left of the total.
CMD_TIMEOUT_SECONDS="${DIAGNOSE_CMD_TIMEOUT_SECONDS:-90}"
TOTAL_TIMEOUT_SECONDS="${DIAGNOSE_TOTAL_TIMEOUT_SECONDS:-600}"
deadline=$((SECONDS + TOTAL_TIMEOUT_SECONDS))

run() {
  local rc remaining budget
  remaining=$((deadline - SECONDS))
  if [ "$remaining" -le 0 ]; then
    echo "(skipped, ${TOTAL_TIMEOUT_SECONDS}s diagnostics budget exhausted: $*)"
    return 0
  fi
  budget="${CMD_TIMEOUT_SECONDS}"
  [ "$remaining" -lt "$budget" ] && budget="$remaining"

  timeout "${budget}" "$@" 2>&1
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "(timed out after ${budget}s: $*)"
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
  # The gateway opens a raw socket for NAT discovery and the datapath health
  # check. When that is refused the log says only
  # `sendmsg: operation not permitted`, which does not distinguish a missing
  # capability from something dropping the packets (#3255). Capture what the
  # pod was actually admitted with, so the next occurrence is conclusive
  # instead of needing a live cluster to answer.
  echo "--- submariner-gateway pod security context / admitting SCC ---"
  run oc --context "$ctx" -n submariner-operator get pods -l app=submariner-gateway \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n  scc: "}{.metadata.annotations.openshift\.io/scc}{"\n  pod securityContext: "}{.spec.securityContext}{"\n  container securityContext: "}{.spec.containers[*].securityContext}{"\n"}{end}'
  # The manifest sets both `airGappedDeployment: true` and `NATTEnable: true`,
  # which pull in opposite directions: an air-gapped deployment should not be
  # running NAT discovery at all, yet that is the code path that fails. Dump
  # what the operator actually received.
  echo "--- deployed Submariner CR spec ---"
  run oc --context "$ctx" -n submariner-operator get submariners.submariner.io -o yaml
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

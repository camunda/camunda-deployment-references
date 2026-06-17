#!/bin/bash
# Best-effort diagnostics for the dual-region Submariner cross-cluster connection.
# Dumps Submariner's own state (gateway pods, Gateway/Endpoint CRs, subctl diagnose)
# to help understand why the cross-cluster tunnel did not establish. Never fails.
set +e

# Support both the 0-indexed (CLUSTER_0/CLUSTER_1) and 1-indexed
# (CLUSTER_1_NAME/CLUSTER_2_NAME) cluster-context naming conventions.
C0="${CLUSTER_0:-${CLUSTER_1_NAME:-}}"
C1="${CLUSTER_1:-${CLUSTER_2_NAME:-}}"

for ctx in "$C0" "$C1"; do
  [ -z "$ctx" ] && continue
  echo "===== Submariner diagnostics for context: ${ctx} ====="
  echo "--- subctl show all ---"
  subctl show all --contexts "$ctx" 2>&1
  echo "--- subctl diagnose all ---"
  subctl diagnose all --context "$ctx" 2>&1
  echo "--- submariner-operator pods ---"
  oc --context "$ctx" -n submariner-operator get pods -o wide 2>&1
  echo "--- submariner-gateway logs (last 200 lines) ---"
  oc --context "$ctx" -n submariner-operator logs -l app=submariner-gateway --tail=200 --prefix 2>&1
  echo "--- Gateway / Endpoint CRs ---"
  oc --context "$ctx" get gateways.submariner.io,endpoints.submariner.io -A -o wide 2>&1
  echo "--- gateway-labelled nodes ---"
  oc --context "$ctx" get nodes -l submariner.io/gateway=true -o wide 2>&1
done

if [ -n "$C0" ]; then
  echo "===== ManagedClusterAddons (hub) ====="
  oc --context "$C0" get managedclusteraddon -A -o wide 2>&1
fi

# Best-effort diagnostics: never fail the `if: failure()` debug step that runs this.
exit 0

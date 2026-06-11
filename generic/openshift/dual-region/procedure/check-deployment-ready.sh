#!/bin/bash

set -euo pipefail

# Wait until the dual-region Camunda deployment is healthy on both clusters.
#
# Self-healing rationale:
#   Cross-region Zeebe brokers resolve their peers over Submariner Lighthouse
#   DNS (*.svc.clusterset.local). If a broker starts before that DNS is fully
#   propagated it can hit NXDOMAIN and hang permanently during
#   `Broker.internalStart` (the management port 9600 never opens, the pod stays
#   "0/1 Running" forever). A longer timeout does not help because the JVM never
#   recovers on its own. Deleting the stuck pod lets the StatefulSet recreate it
#   and it becomes ready within ~1-2 min once clusterset DNS resolves.
#
#   Therefore any Zeebe broker pod that has been Running but not ready for longer
#   than STUCK_BROKER_TIMEOUT_SECONDS is treated as hung and restarted, bounded
#   by MAX_BROKER_RESTARTS attempts per pod.

# How long a broker may stay "Running but not ready" before we consider it hung.
STUCK_BROKER_TIMEOUT_SECONDS="${STUCK_BROKER_TIMEOUT_SECONDS:-360}"
# Maximum number of automatic restarts per broker pod.
MAX_BROKER_RESTARTS="${MAX_BROKER_RESTARTS:-3}"

# Tracks how many times each "context/pod" has been auto-restarted.
declare -A BROKER_RESTARTS

# Returns success when every pod in the namespace is Running and ready.
namespace_ready() {
  local context="$1" namespace="$2"
  [ "$(kubectl --context="$context" get pods -n "$namespace" --field-selector=status.phase!=Running -o name | wc -l)" -eq 0 ] &&
    [ "$(kubectl --context="$context" get pods -n "$namespace" -o json | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false)' | wc -l)" -eq 0 ]
}

# Restarts Zeebe broker pods that have been Running but not ready for too long.
restart_stuck_brokers() {
  local context="$1" namespace="$2"
  # Match broker pods for the configured Helm release (defaults to "camunda"),
  # so the self-heal keeps working when CAMUNDA_RELEASE_NAME is customised.
  local release="${CAMUNDA_RELEASE_NAME:-camunda}"
  local now pod started age count
  now="$(date -u +%s)"

  while read -r pod started; do
    [ -z "$pod" ] && continue
    age=$(( now - $(date -u -d "$started" +%s) ))

    if [ "$age" -lt "$STUCK_BROKER_TIMEOUT_SECONDS" ]; then
      echo "  ↳ $pod is not ready yet (${age}s < ${STUCK_BROKER_TIMEOUT_SECONDS}s), still within startup grace period";
      continue;
    fi

    count="${BROKER_RESTARTS[$context/$pod]:-0}"
    if [ "$count" -ge "$MAX_BROKER_RESTARTS" ]; then
      echo "  ↳ $pod still not ready after ${age}s and ${count} restart(s); giving up on auto-recovery";
      continue;
    fi

    echo "  ⚠️  $pod has been Running but not ready for ${age}s (likely a hung startup over Submariner DNS); restarting it (attempt $((count + 1))/${MAX_BROKER_RESTARTS})";
    kubectl --context="$context" delete pod "$pod" -n "$namespace" --wait=false || true;
    BROKER_RESTARTS["$context/$pod"]=$(( count + 1 ));
  done < <(
    kubectl --context="$context" get pods -n "$namespace" -o json |
      jq -r --arg re "^${release}-zeebe-[0-9]+$" '
        .items[]
        | select(.metadata.name | test($re))
        | select(any(.status.containerStatuses[]?; .ready == false))
        | select(any(.status.containerStatuses[]?; .state.running.startedAt != null))
        | "\(.metadata.name) \([.status.containerStatuses[] | select(.state.running != null) | .state.running.startedAt] | min)"
      '
  )
}

while true; do
  echo "Checking pods in context: $CLUSTER_1_NAME, namespace: $CAMUNDA_NAMESPACE_1";
  kubectl --context="$CLUSTER_1_NAME" get pods -n "$CAMUNDA_NAMESPACE_1" --output=wide;
  if namespace_ready "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1"; then
    echo "All pods are Running and Healthy in context: $CLUSTER_1_NAME, namespace: $CAMUNDA_NAMESPACE_1 - Installation completed!";
  else
    echo "Some pods are not Running or Healthy in context: $CLUSTER_1_NAME, namespace: $CAMUNDA_NAMESPACE_1";
    restart_stuck_brokers "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1";
    sleep 5;
    continue;
  fi

  echo "Checking pods in context: $CLUSTER_2_NAME, namespace: $CAMUNDA_NAMESPACE_2";
  kubectl --context="$CLUSTER_2_NAME" get pods -n "$CAMUNDA_NAMESPACE_2" --output=wide;
  if namespace_ready "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2"; then
    echo "OK: All pods are Running and Healthy in context: $CLUSTER_2_NAME, namespace: $CAMUNDA_NAMESPACE_2 - Installation completed!";
    echo "OK: All pods are healthy across both contexts.";
    # Confirm stability before handing off to the test phase: a broker can flap back
    # to Running-but-not-Ready on a transient clusterset-DNS NXDOMAIN
    # (camunda/camunda#55038) shortly after first becoming Ready. Require the cluster
    # to stay healthy across a short settle window so the multi-region tests start
    # against a stable topology; if it flaps, self-heal and keep polling.
    settle="${STABILITY_SETTLE_SECONDS:-30}";
    echo "Confirming stability over ${settle}s before completing...";
    sleep "$settle";
    if namespace_ready "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1" && namespace_ready "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2"; then
      echo "Still healthy after the settle window. Installation completed.";
      exit 0;
    fi
    echo "A broker flapped during the settle window; self-healing and re-checking.";
    restart_stuck_brokers "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1";
    restart_stuck_brokers "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2";
  else
    echo "Some pods are not Running or Healthy in context: $CLUSTER_2_NAME, namespace: $CAMUNDA_NAMESPACE_2";
    restart_stuck_brokers "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2";
  fi

  sleep 5;
done

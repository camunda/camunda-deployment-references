#!/bin/bash

set -euo pipefail

# This script tracks per-pod restart counts in a bash associative array
# (declare -A), which requires bash >= 4. Fail fast with a clear message on older
# shells (e.g. macOS ships bash 3.2) instead of a cryptic "declare: -A: invalid
# option" later on.
if (( BASH_VERSINFO[0] < 4 )); then
  echo "ERROR: ${BASH_SOURCE[0]##*/} requires bash >= 4 (associative arrays); found bash ${BASH_VERSION}." >&2
  exit 1
fi

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

# Both knobs are consumed in integer comparisons (-lt / -ge) below, so reject a
# non-integer override up-front with a clear message instead of a cryptic
# "integer expression expected" failure mid-run.
case "$STUCK_BROKER_TIMEOUT_SECONDS" in ''|*[!0-9]*)
  echo "ERROR: STUCK_BROKER_TIMEOUT_SECONDS must be a non-negative integer (got '$STUCK_BROKER_TIMEOUT_SECONDS')." >&2; exit 1;;
esac
case "$MAX_BROKER_RESTARTS" in ''|*[!0-9]*)
  echo "ERROR: MAX_BROKER_RESTARTS must be a non-negative integer (got '$MAX_BROKER_RESTARTS')." >&2; exit 1;;
esac

# Tracks how many times each "context/pod" has been auto-restarted.
declare -A BROKER_RESTARTS

# Returns success when every pod in the namespace is Running and ready.
namespace_ready() {
  local context="$1" namespace="$2"
  # A namespace with zero pods is NOT ready: the two checks below both evaluate to 0 on
  # empty output, which would otherwise report a false "Installation completed" if the
  # Helm install failed early or targeted an unexpected namespace/context.
  [ "$(kubectl --context="$context" get pods -n "$namespace" -o name | wc -l)" -gt 0 ] &&
    [ "$(kubectl --context="$context" get pods -n "$namespace" --field-selector=status.phase!=Running -o name | wc -l)" -eq 0 ] &&
    [ "$(kubectl --context="$context" get pods -n "$namespace" -o json | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false)' | wc -l)" -eq 0 ]
}

# Restarts Zeebe broker pods that have been Running but not ready for too long.
restart_stuck_brokers() {
  local context="$1" namespace="$2"
  # Match broker pods for the configured Helm release (defaults to "camunda"),
  # so the self-heal keeps working when CAMUNDA_RELEASE_NAME is customised.
  local release="${CAMUNDA_RELEASE_NAME:-camunda}"
  local now pod started_epoch age count
  now="$(date -u +%s)"

  while read -r pod started_epoch; do
    [ -z "$pod" ] && continue
    # started_epoch is emitted by jq (fromdateiso8601) below, so we avoid the
    # GNU-only `date -d <string>` parse and stay portable across BSD/macOS.
    age=$(( now - started_epoch ))

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
    # Only consume a restart attempt when the delete actually succeeds: a transient
    # API error (or an already-gone pod) must not burn the MAX_BROKER_RESTARTS budget.
    if kubectl --context="$context" delete pod "$pod" -n "$namespace" --wait=false; then
      BROKER_RESTARTS["$context/$pod"]=$(( count + 1 ));
    else
      echo "  ↳ failed to delete $pod; will retry without consuming a restart attempt";
    fi
  done < <(
    kubectl --context="$context" get pods -n "$namespace" -o json |
      jq -r --arg re "^${release}-zeebe-[0-9]+$" '
        .items[]
        | select(.metadata.name | test($re))
        | select(any(.status.containerStatuses[]?; .ready == false))
        | select(any(.status.containerStatuses[]?; .state.running.startedAt != null))
        | "\(.metadata.name) \([.status.containerStatuses[] | select(.state.running != null) | (.state.running.startedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)] | min)"
      '
  )
}

while true; do
  echo "Checking pods in context: $CLUSTER_0, namespace: $CAMUNDA_NAMESPACE_0";
  kubectl --context="$CLUSTER_0" get pods -n "$CAMUNDA_NAMESPACE_0" --output=wide;
  if namespace_ready "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0"; then
    echo "All pods are Running and Healthy in context: $CLUSTER_0, namespace: $CAMUNDA_NAMESPACE_0 - Installation completed!";
  else
    echo "Some pods are not Running or Healthy in context: $CLUSTER_0, namespace: $CAMUNDA_NAMESPACE_0";
    restart_stuck_brokers "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0";
    sleep 5;
    continue;
  fi

  echo "Checking pods in context: $CLUSTER_1, namespace: $CAMUNDA_NAMESPACE_1";
  kubectl --context="$CLUSTER_1" get pods -n "$CAMUNDA_NAMESPACE_1" --output=wide;
  if namespace_ready "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1"; then
    echo "OK: All pods are Running and Healthy in context: $CLUSTER_1, namespace: $CAMUNDA_NAMESPACE_1 - Installation completed!";
    echo "OK: All pods are healthy across both contexts.";
    # Confirm stability before handing off to the test phase: a broker can flap back
    # to Running-but-not-Ready on a transient clusterset-DNS NXDOMAIN
    # (camunda/camunda#55038) shortly after first becoming Ready. Require the cluster
    # to stay healthy across a short settle window so the multi-region tests start
    # against a stable topology; if it flaps, self-heal and keep polling.
    settle="${STABILITY_SETTLE_SECONDS:-30}";
    echo "Confirming stability over ${settle}s before completing...";
    sleep "$settle";
    if namespace_ready "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" && namespace_ready "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1"; then
      echo "Still healthy after the settle window. Installation completed.";
      exit 0;
    fi
    echo "A broker flapped during the settle window; self-healing and re-checking.";
    restart_stuck_brokers "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0";
    restart_stuck_brokers "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1";
  else
    echo "Some pods are not Running or Healthy in context: $CLUSTER_1, namespace: $CAMUNDA_NAMESPACE_1";
    restart_stuck_brokers "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1";
  fi

  sleep 5;
done

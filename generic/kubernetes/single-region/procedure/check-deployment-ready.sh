#!/bin/bash

# Wait until every pod of the Camunda namespace is Running with all of its
# containers ready.
#
# The wait is bounded and reports *why* it is still waiting: a stuck deployment
# used to render as an endless stream of "Some pods are not Running or Healthy",
# which hides the only information that matters (CrashLoopBackOff, OOMKilled,
# ImagePullBackOff, unschedulable pods...).
#
# Configuration (all optional, sensible defaults):
#   CAMUNDA_NAMESPACE                  namespace Camunda is installed in (default: camunda)
#   DEPLOYMENT_READY_TIMEOUT_SECONDS   wall-clock budget in seconds, 0 to wait forever (default: 1800)
#   DEPLOYMENT_READY_INTERVAL_SECONDS  delay between two polls in seconds (default: 5)

set -uo pipefail

namespace="${CAMUNDA_NAMESPACE:-camunda}"
timeout_seconds="${DEPLOYMENT_READY_TIMEOUT_SECONDS:-1800}"
interval_seconds="${DEPLOYMENT_READY_INTERVAL_SECONDS:-5}"

# Require plain non-negative integers; fall back to the defaults otherwise. The
# digits-only check rejects signs/letters before the 10# normalization (which also
# stops a leading zero from being read as octal in the arithmetic below).
case "$timeout_seconds" in
    '' | *[!0-9]*)
        echo "WARNING: DEPLOYMENT_READY_TIMEOUT_SECONDS='${timeout_seconds}' is not a non-negative integer; using 1800." >&2
        timeout_seconds=1800
        ;;
esac
timeout_seconds=$((10#$timeout_seconds))

case "$interval_seconds" in
    '' | 0 | *[!0-9]*)
        echo "WARNING: DEPLOYMENT_READY_INTERVAL_SECONDS='${interval_seconds}' is not a positive integer; using 5." >&2
        interval_seconds=5
        ;;
esac
interval_seconds=$((10#$interval_seconds))

# Snapshot of the namespace, or an empty string when the call fails. Callers must
# treat an empty result as "nothing to report" rather than letting `kubectl` error
# text reach `jq`, which would turn a transient API error into a parse-error storm
# in the middle of the diagnostics.
pods_json() {
    kubectl get pods -n "$namespace" -o json 2>/dev/null
}

# Containers that are not ready, with the reason they are waiting and how their
# previous attempt died. 'OOMKilled' or a non-zero exit code here is the actual
# root cause, and is what a component needing more resources looks like.
# Takes the namespace snapshot as its first argument.
report_unready_containers() {
    [ -n "$1" ] || return 0
    printf '%s' "$1" | jq -r '
        .items[]
        | . as $pod
        | (($pod.status.containerStatuses // []) + ($pod.status.initContainerStatuses // []))[]
        | select(.ready != true)
        | "  \($pod.metadata.name)/\(.name)"
          + " phase=\($pod.status.phase)"
          + " restarts=\(.restartCount)"
          + " waiting=\(.state.waiting.reason // "-")"
          + " lastTerminated=\(.lastState.terminated.reason // "-")"
          + " exitCode=\(.lastState.terminated.exitCode // "-")"
    ' 2>/dev/null
}

# Pods that never reached the Running phase have no container status to report,
# so surface them separately (Pending pods are usually unschedulable ones).
# Takes the namespace snapshot as its first argument.
report_non_running_pods() {
    [ -n "$1" ] || return 0
    printf '%s' "$1" | jq -r '
        .items[]
        | select(.status.phase != "Running")
        | "  \(.metadata.name) phase=\(.status.phase) reason=\(.status.reason // "-")"
    ' 2>/dev/null
}

# Warning events only. `--no-headers` keeps the column header out of the output so
# an empty result stays empty and `diagnostics` can skip the whole section instead
# of printing a heading with nothing under it.
report_warning_events() {
    kubectl get events -n "$namespace" \
        --field-selector type=Warning \
        --sort-by=.lastTimestamp \
        --no-headers \
        -o custom-columns=OBJECT:.involvedObject.name,REASON:.reason,MESSAGE:.message \
        2>/dev/null | grep -v '^No resources found' | tail -n 15
}

diagnostics() {
    local pods unready non_running events
    local listing_failed=false
    # One snapshot for the whole report: two independent calls could describe
    # different moments and contradict each other in the same output. Key the
    # failure message off the exit status rather than off an empty result: with
    # `-o json` an empty namespace still yields a parseable List, so emptiness
    # alone would not tell the two apart.
    pods="$(pods_json)" || listing_failed=true
    unready="$(report_unready_containers "$pods")"
    non_running="$(report_non_running_pods "$pods")"
    events="$(report_warning_events)"

    echo "--- why the deployment is not ready yet ---"
    # A failed listing means the tool saw nothing at all. Say so, otherwise the
    # report is an empty header/footer pair and the reader cannot tell a broken
    # API call from a converging deployment.
    if [ "$listing_failed" = "true" ]; then
        echo "Could not list pods in namespace '${namespace}'; the API call failed or the namespace does not exist."
    elif [ -z "$non_running" ] && [ -z "$unready" ] && [ -z "$events" ]; then
        # Reached only when the readiness check refused an otherwise clean
        # snapshot, which in practice means the namespace holds no pod yet.
        echo "No unready pod and no warning event found; the namespace holds no pod yet, or its workloads are still being created."
    fi
    [ -n "$non_running" ] && printf 'Pods not Running:\n%s\n' "$non_running"
    [ -n "$unready" ] && printf 'Containers not ready:\n%s\n' "$unready"
    if [ -n "$events" ]; then
        printf 'Recent warning events:\n%s\n' "$events"
    fi
    echo "-------------------------------------------"
}

all_pods_ready() {
    local pods total
    # Evaluate both conditions from a single snapshot: two independent `kubectl`
    # calls could disagree, and a failing call used to yield an empty result that
    # was counted as "nothing unhealthy" and reported the install as complete.
    pods="$(pods_json)" || return 1
    [ -n "$pods" ] || return 1

    total="$(printf '%s' "$pods" | jq -r '.items | length' 2>/dev/null)"
    case "$total" in
        '' | *[!0-9]*) return 1 ;;
        0) return 1 ;; # an empty namespace is not a healthy deployment
    esac

    [ "$(printf '%s' "$pods" | jq -r '[.items[] | select(.status.phase != "Running")] | length')" -eq 0 ] &&
        [ "$(printf '%s' "$pods" | jq -r '[.items[] | select(.status.containerStatuses[]?.ready == false)] | length')" -eq 0 ]
}

if [ "$timeout_seconds" -gt 0 ]; then
    deadline=$(($(date +%s) + timeout_seconds))
    echo "Waiting up to ${timeout_seconds}s for all pods in namespace '${namespace}' to be ready..."
else
    deadline=0
    echo "Waiting (no timeout) for all pods in namespace '${namespace}' to be ready..."
fi

# Report the detailed state roughly once a minute so the output stays readable
# while still explaining what is blocking the deployment.
diagnostics_every=$(((60 + interval_seconds - 1) / interval_seconds))
attempt=0

while true; do
    kubectl get pods -n "$namespace" --output=wide

    if all_pods_ready; then
        echo "All pods are Running and Healthy - Installation completed!"
        exit 0
    fi

    attempt=$((attempt + 1))
    if [ $((attempt % diagnostics_every)) -eq 0 ]; then
        diagnostics
    fi

    if [ "$deadline" -ne 0 ] && [ "$(date +%s)" -ge "$deadline" ]; then
        echo "ERROR: pods in namespace '${namespace}' were still not ready after ${timeout_seconds}s." >&2
        diagnostics
        exit 1
    fi

    echo "Some pods are not Running or Healthy, please wait..."
    sleep "$interval_seconds"
done

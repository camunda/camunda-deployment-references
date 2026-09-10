#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Runs a steady process-instance load against the cluster, from inside one of
# its regions.
#
#   ./load-generator.sh start [slot]
#   ./load-generator.sh status [slot]
#   ./load-generator.sh stop [slot]
#
# Why this exists: every other check in this suite samples the cluster at a
# point in time, so none of them can show what happens *during* a region loss.
# verify-exported-data.sh says as much in its own header: it records a known set
# of instances before the outage and looks for them after, and widening that
# window to cover the outage itself needs a generator writing continuously.
#
# It also gives the demo its one honest visual. A throughput number that dips
# for a Raft re-election and recovers, with no operator command in between, is
# the architecture's whole claim in a single line of output.
#
# The generator runs as a Job *in* a cluster rather than from a laptop. A
# port-forward would have to be re-established when the region under test goes
# away, and load pointed at that region would stop exactly when the interesting
# part starts.
#
# Tunables:
#   LOAD_RATE               process instances per second (default 5)
#   LOAD_DURATION_SECONDS   deadline if nobody runs `stop` (default 3600)
#   LOAD_IMAGE              benchmark image

: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"
: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib-management-api.sh
. "$SCRIPT_DIR/lib-management-api.sh"

export LOAD_RATE="${LOAD_RATE:-5}"
export LOAD_DURATION_SECONDS="${LOAD_DURATION_SECONDS:-3600}"
export LOAD_IMAGE="${LOAD_IMAGE:-camundacommunityhub/camunda-8-benchmark:main}"

JOB_MANIFEST="$SCRIPT_DIR/manifests/load-generator.job.yml"
PROCESS_RESOURCE="$SCRIPT_DIR/resources/load-generator.bpmn"
JOB_NAME="camunda-load-generator"
CONFIGMAP_NAME="camunda-load-generator-process"
SECRET_NAME="camunda-load-generator-auth"

MODE="${1:-}"
SLOT="${2:-}"

if [ -z "$MODE" ]; then
    echo "usage: $0 <start|status|stop> [slot]" >&2
    exit 1
fi

# Default to the last active slot. Slot 0 hosts the Aurora writer and is
# therefore the slot a region-loss test is most likely to remove, which would
# take the generator down with it.
if [ -z "$SLOT" ]; then
    SLOT=$((CAMUNDA_ACTIVE_REGIONS - 1))
fi
camunda::require_slot "$SLOT" "the load generator slot"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
CONTEXT="${contexts[$SLOT]}"

load::start() {
    : "${CAMUNDA_BASIC_AUTH_USER:?CAMUNDA_BASIC_AUTH_USER must be set, source export_environment_prerequisites.sh}"
    : "${CAMUNDA_BASIC_AUTH_PASSWORD:?CAMUNDA_BASIC_AUTH_PASSWORD must be set, source export_environment_prerequisites.sh}"

    echo "--> Load generator target: slot $SLOT ($(camunda::zone_name "$SLOT")), context $CONTEXT"
    echo "    ${LOAD_RATE} process instance(s)/s for up to ${LOAD_DURATION_SECONDS}s"

    kubectl --context "$CONTEXT" create configmap "$CONFIGMAP_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-file="$PROCESS_RESOURCE" \
        --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -

    kubectl --context "$CONTEXT" create secret generic "$SECRET_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-literal=username="$CAMUNDA_BASIC_AUTH_USER" \
        --from-literal=password="$CAMUNDA_BASIC_AUTH_PASSWORD" \
        --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -

    # A Job's pod template is immutable, so a re-run replaces rather than
    # patches. Deleting first keeps `start` idempotent.
    kubectl --context "$CONTEXT" delete job "$JOB_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" --ignore-not-found --wait=true

    envsubst <"$JOB_MANIFEST" | kubectl --context "$CONTEXT" apply -f -

    echo "--> Waiting for the generator pod to start"
    kubectl --context "$CONTEXT" wait --for=condition=ready pod \
        --namespace "$CAMUNDA_NAMESPACE" \
        --selector "app=$JOB_NAME" --timeout=300s

    echo
    echo "Follow the rate with:"
    echo "  kubectl --context $CONTEXT --namespace $CAMUNDA_NAMESPACE logs -f job/$JOB_NAME"
}

load::status() {
    kubectl --context "$CONTEXT" get job "$JOB_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" --ignore-not-found

    kubectl --context "$CONTEXT" get pods \
        --namespace "$CAMUNDA_NAMESPACE" --selector "app=$JOB_NAME"

    echo
    echo "--> Last reported throughput"
    # The benchmark prints a periodic summary line; the tail is the current rate.
    kubectl --context "$CONTEXT" logs "job/$JOB_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" --tail=15 2>/dev/null ||
        echo "    no logs yet"
}

load::stop() {
    echo "--> Stopping the load generator in $CONTEXT"
    kubectl --context "$CONTEXT" delete job "$JOB_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" --ignore-not-found --wait=true
    kubectl --context "$CONTEXT" delete configmap "$CONFIGMAP_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" --ignore-not-found
    kubectl --context "$CONTEXT" delete secret "$SECRET_NAME" \
        --namespace "$CAMUNDA_NAMESPACE" --ignore-not-found

    # The instances it produced are deliberately left in place: they are the
    # exported data a failover is meant not to lose.
    echo "Process instances created by the generator are left in the cluster."
}

case "$MODE" in
start) load::start ;;
status) load::status ;;
stop) load::stop ;;
*)
    echo "usage: $0 <start|status|stop> [slot]" >&2
    exit 1
    ;;
esac

#!/bin/bash
set -euo pipefail

# Asserts that the cluster still works after losing one region.
#
#   ./verify-degraded-cluster.sh <lost-slot>
#
# The point of the multi-region topology is that this state is NOT an outage:
# every partition keeps a majority of its replicas. The checks below prove
# quorum and API availability, not completeness of the replica set.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"

if [ $# -ne 1 ]; then
    echo "usage: $0 <lost-region-slot>" >&2
    exit 1
fi

LOST_SLOT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib-management-api.sh
. "$SCRIPT_DIR/lib-management-api.sh"
OUTPUT_FILE="${OUTPUT_FILE:-degraded-topology.json}"

survivor_context="$(camunda::survivor_context "$LOST_SLOT")"

echo "Verifying the surviving cluster from $survivor_context"

expected_survivors=$((CAMUNDA_BROKERS_PER_REGION * (CAMUNDA_ACTIVE_REGIONS - 1)))
deadline=$((SECONDS + ${VERIFY_DEGRADED_TIMEOUT_SECONDS:-900}))

echo "--> Waiting for the topology to converge on $expected_survivors surviving broker(s)"
while true; do
    # A tunnel per poll. This runs right after a region was lost, when the
    # surviving gateways are the most likely to restart, and a tunnel that died
    # with one of them would otherwise report zero brokers until the deadline:
    # "the cluster is gone" for what is only "the tunnel is gone".
    # Redirected rather than captured: `$(...)` would run the helper in a
    # subshell and CAMUNDA_LAST_STATUS would not survive it.
    camunda::gateway_get "$survivor_context" /v2/topology >"$OUTPUT_FILE" 2>/dev/null || true

    # jq exits 0 on an empty file while printing nothing, so `|| echo 0` never
    # fires and the comparison below would be `[ "" -ge n ]`.
    brokers="$(jq '.brokers | length // 0' "$OUTPUT_FILE" 2>/dev/null || true)"
    brokers="${brokers:-0}"
    if [ "$brokers" -ge "$expected_survivors" ]; then
        echo "    $brokers broker(s) reachable."
        break
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ERROR: only $brokers broker(s) reachable, expected at least $expected_survivors." >&2
        echo "       Last status: HTTP $CAMUNDA_LAST_STATUS." >&2
        cat "$OUTPUT_FILE" >&2 2>/dev/null || true
        exit 1
    fi

    echo "    $brokers/$expected_survivors reachable, waiting ..."
    sleep 15
done

echo "--> Checking that every partition still has a leader"
partitions="$(jq '.partitionsCount' "$OUTPUT_FILE")"
partitions_with_leader="$(jq '
    [.brokers[].partitions[] | select(.role == "leader") | .partitionId] | unique | length' "$OUTPUT_FILE")"

if [ "$partitions_with_leader" -lt "$partitions" ]; then
    echo "ERROR: only $partitions_with_leader of $partitions partitions have a leader." >&2
    echo "       The surviving regions did not keep a quorum. Check that" >&2
    echo "       replicationFactor equals the region slot count." >&2
    cat "$OUTPUT_FILE" >&2 2>/dev/null || true
    exit 1
fi
echo "    all $partitions partitions have a leader."

echo "--> Checking that the gateway still serves the v2 API"
# A quorum loss shows up to a client as a timeout or a 5xx. Anything the gateway
# answers itself, including an authorisation error, proves it is serving, so the
# status matters here and the body does not.
camunda::gateway_get "$survivor_context" /v2/license >/dev/null 2>&1 || true
response="$CAMUNDA_LAST_STATUS"

case "$response" in
2* | 401 | 403)
    echo "    gateway responded with HTTP $response."
    ;;
*)
    echo "ERROR: the gateway returned HTTP $response, it is not serving requests." >&2
    exit 1
    ;;
esac

echo
echo "The cluster kept quorum and API availability after losing region slot $LOST_SLOT."

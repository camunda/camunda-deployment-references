#!/bin/bash
set -euo pipefail

# Asserts that the cluster still works after losing one region.
#
#   ./verify-degraded-cluster.sh <lost-slot>
#
# The point of the multi-region topology is that this state is NOT an outage:
# every partition keeps a majority of its replicas, so the engine accepts new
# work. The checks below are therefore about liveness, not about completeness of
# the replica set.

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
CAMUNDA_BASIC_AUTH_USER="${CAMUNDA_BASIC_AUTH_USER:-demo}"
CAMUNDA_BASIC_AUTH_PASSWORD="${CAMUNDA_BASIC_AUTH_PASSWORD:-demo}"
LOCAL_PORT="${LOCAL_PORT:-8080}"

survivor_context="$(camunda::survivor_context "$LOST_SLOT")"

echo "Verifying the surviving cluster from $survivor_context"

kubectl --context "$survivor_context" -n "$CAMUNDA_NAMESPACE" \
    port-forward "svc/${CAMUNDA_RELEASE_NAME}-zeebe-gateway" "${LOCAL_PORT}:8080" >/dev/null 2>&1 &
port_forward_pid=$!
# shellcheck disable=SC2064
trap "kill $port_forward_pid 2>/dev/null || true" EXIT
sleep 5

expected_survivors=$((CAMUNDA_BROKERS_PER_REGION * (CAMUNDA_ACTIVE_REGIONS - 1)))
deadline=$((SECONDS + ${VERIFY_DEGRADED_TIMEOUT_SECONDS:-900}))

echo "--> Waiting for the topology to converge on $expected_survivors surviving broker(s)"
while true; do
    topology="$(curl -sS -u "${CAMUNDA_BASIC_AUTH_USER}:${CAMUNDA_BASIC_AUTH_PASSWORD}" \
        "http://localhost:${LOCAL_PORT}/v2/topology" || echo '{}')"

    brokers="$(echo "$topology" | jq '.brokers | length // 0')"
    if [ "$brokers" -ge "$expected_survivors" ]; then
        echo "    $brokers broker(s) reachable."
        break
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ERROR: only $brokers broker(s) reachable, expected at least $expected_survivors." >&2
        echo "$topology" >&2
        exit 1
    fi

    echo "    $brokers/$expected_survivors reachable, waiting ..."
    sleep 15
done

echo "--> Checking that every partition still has a leader"
partitions="$(echo "$topology" | jq '.partitionsCount')"
partitions_with_leader="$(echo "$topology" | jq '
    [.brokers[].partitions[] | select(.role == "leader") | .partitionId] | unique | length')"

if [ "$partitions_with_leader" -lt "$partitions" ]; then
    echo "ERROR: only $partitions_with_leader of $partitions partitions have a leader." >&2
    echo "       The surviving regions did not keep a quorum. Check that" >&2
    echo "       replicationFactor equals the region slot count." >&2
    echo "$topology" >&2
    exit 1
fi
echo "    all $partitions partitions have a leader."

echo "--> Checking that the gateway still serves the v2 API"
# A quorum loss shows up to a client as a timeout or a 5xx. Anything the gateway
# answers itself, including an authorisation error, proves it is serving.
#
# `|| true` rather than `|| echo 000`: curl already reports 000 through -w when
# it cannot connect, so echoing a fallback appends a second one and reports
# "HTTP 000000".
response="$(curl -sS -o /dev/null -w '%{http_code}' \
    -u "${CAMUNDA_BASIC_AUTH_USER}:${CAMUNDA_BASIC_AUTH_PASSWORD}" \
    "http://localhost:${LOCAL_PORT}/v2/license" 2>/dev/null || true)"
response="${response:-000}"

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
echo "The cluster survived the loss of region slot $LOST_SLOT without intervention."

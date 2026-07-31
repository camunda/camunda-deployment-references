#!/bin/bash
set -euo pipefail

# Prints the Zeebe cluster topology and asserts the expected multi-region shape:
#
#   * clusterSize brokers are known
#   * every region slot hosts exactly CAMUNDA_BROKERS_PER_REGION brokers,
#     identified by nodeId % regionSlots == regionId
#   * partitionCount and replicationFactor match the configuration
#   * no partition is unhealthy
#
# Brokers belonging to slots that are not deployed yet are reported as missing
# rather than treated as a failure, which is the expected state while a cluster
# is grown one region at a time.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_PARTITION_COUNT:?CAMUNDA_PARTITION_COUNT must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REPLICATION_FACTOR:?CAMUNDA_REPLICATION_FACTOR must be set, source export_environment_prerequisites.sh}"

CAMUNDA_BASIC_AUTH_USER="${CAMUNDA_BASIC_AUTH_USER:-demo}"
CAMUNDA_BASIC_AUTH_PASSWORD="${CAMUNDA_BASIC_AUTH_PASSWORD:-demo}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
OUTPUT_FILE="${OUTPUT_FILE:-zeebe-topology.json}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
# Query through the first active region; any gateway returns the whole topology.
context="${contexts[0]}"

kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" \
    port-forward "svc/${CAMUNDA_RELEASE_NAME}-zeebe-gateway" "${LOCAL_PORT}:8080" >/dev/null 2>&1 &
port_forward_pid=$!
# shellcheck disable=SC2064
trap "kill $port_forward_pid 2>/dev/null || true" EXIT

sleep 5

# A stretched cluster does not converge instantly: brokers dial each other
# across regions, and the README budgets 10-20 minutes for the Raft cluster to
# form. Poll until the expected broker count is reached rather than sampling
# once, which would report a transient state as a failure.
expected_brokers=$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_ACTIVE_REGIONS))
deadline=$((SECONDS + ${TOPOLOGY_TIMEOUT_SECONDS:-1500}))

echo "Waiting for $expected_brokers broker(s) to join the cluster ..."
while true; do
    http_code="$(curl -sS -u "${CAMUNDA_BASIC_AUTH_USER}:${CAMUNDA_BASIC_AUTH_PASSWORD}" \
        -o "$OUTPUT_FILE" -w '%{http_code}' \
        "http://localhost:${LOCAL_PORT}/v2/topology" || echo 000)"

    case "$http_code" in
    401 | 403)
        # Not a convergence problem and retrying will not fix it: the gateway
        # answered and rejected the credentials.
        echo "ERROR: the gateway rejected the basic-auth credentials (HTTP $http_code)." >&2
        echo "       CAMUNDA_BASIC_AUTH_USER must match a user the chart provisions;" >&2
        echo "       in CI that is the overlay passed through CAMUNDA_EXTRA_VALUES." >&2
        exit 1
        ;;
    2*)
        current="$(jq '.brokers | length // 0' "$OUTPUT_FILE" 2>/dev/null || echo 0)"
        if [ "$current" -ge "$expected_brokers" ]; then
            echo "  $current/$expected_brokers brokers present."
            break
        fi
        ;;
    *)
        current="gateway unreachable (HTTP $http_code)"
        ;;
    esac

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ERROR: the cluster did not converge within ${TOPOLOGY_TIMEOUT_SECONDS:-1500}s." >&2
        echo "       Last observation: $current, expected $expected_brokers." >&2
        cat "$OUTPUT_FILE" >&2 2>/dev/null || true
        exit 1
    fi

    echo "  $current/$expected_brokers, waiting ..."
    sleep 20
done

echo "Topology written to $OUTPUT_FILE"
jq . "$OUTPUT_FILE"

expected_brokers=$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_ACTIVE_REGIONS))
actual_brokers="$(jq '.brokers | length' "$OUTPUT_FILE")"
actual_partitions="$(jq '.partitionsCount' "$OUTPUT_FILE")"
actual_replication="$(jq '.replicationFactor' "$OUTPUT_FILE")"

failures=0
fail() {
    echo "FAIL: $1" >&2
    failures=$((failures + 1))
}

[ "$actual_brokers" = "$expected_brokers" ] ||
    fail "expected $expected_brokers brokers for $CAMUNDA_ACTIVE_REGIONS active region(s), got $actual_brokers"
[ "$actual_partitions" = "$CAMUNDA_PARTITION_COUNT" ] ||
    fail "expected partitionsCount $CAMUNDA_PARTITION_COUNT, got $actual_partitions"
[ "$actual_replication" = "$CAMUNDA_REPLICATION_FACTOR" ] ||
    fail "expected replicationFactor $CAMUNDA_REPLICATION_FACTOR, got $actual_replication"

echo
echo "Broker distribution across region slots (nodeId % $CAMUNDA_REGION_SLOTS):"
for ((slot = 0; slot < CAMUNDA_REGION_SLOTS; slot++)); do
    count="$(jq --argjson slots "$CAMUNDA_REGION_SLOTS" --argjson slot "$slot" \
        '[.brokers[] | select(.nodeId % $slots == $slot)] | length' "$OUTPUT_FILE")"

    if [ "$slot" -lt "$CAMUNDA_ACTIVE_REGIONS" ]; then
        echo "  slot $slot: $count broker(s)"
        [ "$count" = "$CAMUNDA_BROKERS_PER_REGION" ] ||
            fail "region slot $slot hosts $count broker(s), expected $CAMUNDA_BROKERS_PER_REGION"
    else
        echo "  slot $slot: $count broker(s) (slot not activated yet)"
    fi
done

unhealthy="$(jq '[.brokers[].partitions[] | select(.health != "healthy")] | length' "$OUTPUT_FILE")"
echo
echo "Unhealthy partition replicas: $unhealthy"
[ "$unhealthy" = "0" ] || fail "$unhealthy partition replica(s) are not healthy"

if [ "$failures" -ne 0 ]; then
    echo
    echo "$failures topology check(s) failed." >&2
    exit 1
fi

echo
echo "Topology matches the expected multi-region shape."

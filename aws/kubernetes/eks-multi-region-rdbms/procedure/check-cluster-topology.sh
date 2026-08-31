#!/bin/bash
set -euo pipefail

# Prints the Zeebe cluster topology and asserts the expected multi-region shape:
#
#   * clusterSize brokers are known
#   * every zone hosts exactly CAMUNDA_BROKERS_PER_REGION brokers
#   * partitionCount and replicationFactor match the configuration
#   * no partition is unhealthy
#
# Brokers belonging to zones that are not deployed yet are reported as missing
# rather than treated as a failure, which is the expected state while a cluster
# is grown one zone at a time.
#
# Zone attribution reads `brokerId`, the composite `<zone>_<index>` a zone-aware
# broker reports. Not `nodeId`: that one is the index INSIDE the zone, so it
# repeats across zones and every zone would look like the first ones.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ZONE_NAMES:?CAMUNDA_ZONE_NAMES must be set, source export-terraform-outputs.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_PARTITION_COUNT:?CAMUNDA_PARTITION_COUNT must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REPLICATION_FACTOR:?CAMUNDA_REPLICATION_FACTOR must be set, source export_environment_prerequisites.sh}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib-management-api.sh
. "$SCRIPT_DIR/lib-management-api.sh"

OUTPUT_FILE="${OUTPUT_FILE:-zeebe-topology.json}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
# Query through the first active region; any gateway returns the whole topology.
context="${contexts[0]}"

# A stretched cluster does not converge instantly: brokers dial each other
# across regions, and the README budgets 10-20 minutes for the Raft cluster to
# form. Poll until the expected broker count is reached rather than sampling
# once, which would report a transient state as a failure.
expected_brokers=$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_ACTIVE_REGIONS))
deadline=$((SECONDS + ${TOPOLOGY_TIMEOUT_SECONDS:-1500}))

echo "Waiting for $expected_brokers broker(s) to join the cluster ..."
while true; do
    # Each poll opens its own tunnel, so a gateway that restarted between two of
    # them costs one iteration rather than the rest of the wait.
    if camunda::gateway_get "$context" /v2/topology >"$OUTPUT_FILE" 2>/dev/null; then
        current="$(jq '.brokers | length // 0' "$OUTPUT_FILE" 2>/dev/null || echo 0)"
        if [ "$current" -ge "$expected_brokers" ]; then
            echo "  $current/$expected_brokers brokers present."
            break
        fi
    elif [ "$CAMUNDA_LAST_STATUS" = "401" ] || [ "$CAMUNDA_LAST_STATUS" = "403" ]; then
        # Retryable, despite looking definitive. The gateway starts answering
        # before the security layer finishes initialising, so it rejects valid
        # credentials for the first minutes of a cold start. Treating this as a
        # hard failure reports a starting cluster as a misconfigured one; the
        # dual-region suite carries an equivalent wait for the same reason.
        # A genuine credentials mismatch simply never clears, and is reported
        # against the deadline below.
        current="auth not ready (HTTP $CAMUNDA_LAST_STATUS)"
    else
        current="gateway unreachable (HTTP $CAMUNDA_LAST_STATUS)"
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ERROR: the cluster did not converge within ${TOPOLOGY_TIMEOUT_SECONDS:-1500}s." >&2
        echo "       Last observation: $current, expected $expected_brokers." >&2
        case "$CAMUNDA_LAST_STATUS" in
        401 | 403)
            echo "       The gateway never accepted the credentials, so this is a" >&2
            echo "       configuration problem rather than a slow start:" >&2
            echo "       CAMUNDA_BASIC_AUTH_USER must match a user the chart provisions." >&2
            echo "       In CI that is the overlay passed through CAMUNDA_EXTRA_VALUES." >&2
            ;;
        esac
        cat "$OUTPUT_FILE" >&2 2>/dev/null || true
        exit 1
    fi

    echo "  $current/$expected_brokers, waiting ..."
    sleep 20
done

echo "Topology written to $OUTPUT_FILE"
jq . "$OUTPUT_FILE"

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

read -r -a _zone_names <<<"$CAMUNDA_ZONE_NAMES"

echo
echo "Broker distribution across zones:"
for ((slot = 0; slot < CAMUNDA_REGION_SLOTS; slot++)); do
    zone="${_zone_names[$slot]:-slot-$slot}"

    # Strip the trailing index off `brokerId`, rather than splitting on the first
    # underscore, so a zone whose name contains one still resolves.
    count="$(jq --arg zone "$zone" \
        '[.brokers[] | select((.brokerId | sub("_[0-9]+$"; "")) == $zone)] | length' \
        "$OUTPUT_FILE")"

    if [ "$slot" -lt "$CAMUNDA_ACTIVE_REGIONS" ]; then
        echo "  $zone: $count broker(s)"
        [ "$count" = "$CAMUNDA_BROKERS_PER_REGION" ] ||
            fail "zone $zone hosts $count broker(s), expected $CAMUNDA_BROKERS_PER_REGION"
    else
        echo "  $zone: $count broker(s) (zone not activated yet)"
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

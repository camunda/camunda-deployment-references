#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Handles the loss of one region.
#
#   ./failover.sh <lost-region-slot> [--unplanned] [--drain-brokers]
#
# With `replicationFactor == regionSlots` and at least three slots, losing one
# region leaves every partition with a majority of its replicas: Zeebe keeps
# processing and NO Zeebe action is required. That is the entire point of this
# topology, and the difference with the dual-region architecture, where a region
# loss halts the cluster until brokers are force-removed.
#
# What still needs attention is the database, because Aurora Global Database has
# a single writer region:
#
#   * If the writer was NOT in the lost region, nothing to do.
#   * Planned (region still reachable): `failover-global-cluster` performs a
#     switchover with no data loss.
#   * Unplanned (region gone): `remove-from-global-cluster` detaches and
#     promotes a surviving member. Replication lag at the time of the outage is
#     lost, and the global cluster must be rebuilt during failback.
#
# `--drain-brokers` additionally removes the lost brokers from the Zeebe cluster.
# Use it only when the region will stay down long enough that running the
# surviving regions at full replication factor is worth a partition
# reconfiguration; failback then has to add the brokers back explicitly.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${AWS_REGIONS:?AWS_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"

if [ $# -lt 1 ]; then
    echo "usage: $0 <lost-region-slot> [--unplanned] [--drain-brokers]" >&2
    exit 1
fi

LOST_SLOT="$1"
shift
UNPLANNED=false
DRAIN_BROKERS=false
for arg in "$@"; do
    case "$arg" in
    --unplanned) UNPLANNED=true ;;
    --drain-brokers) DRAIN_BROKERS=true ;;
    *)
        echo "unknown argument: $arg" >&2
        exit 1
        ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-management-api.sh"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
read -r -a aws_regions <<<"$AWS_REGIONS"

# Pick any surviving region to drive the management API from.
survivor_slot=-1
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    if [ "$i" -ne "$LOST_SLOT" ]; then
        survivor_slot="$i"
        break
    fi
done
if [ "$survivor_slot" -lt 0 ]; then
    echo "ERROR: no surviving region left." >&2
    exit 1
fi
survivor_context="${contexts[$survivor_slot]}"

echo "==============================================================="
echo " Region slot $LOST_SLOT (${aws_regions[$LOST_SLOT]}) declared lost"
echo " Driving the procedure from region slot $survivor_slot ($survivor_context)"
echo "==============================================================="

###############################################################################
# 1. Zeebe: report, do not act                                                #
###############################################################################

surviving_regions=$((CAMUNDA_ACTIVE_REGIONS - 1))
echo
echo "--> Zeebe quorum check"
echo "    replicationFactor    : ${CAMUNDA_REPLICATION_FACTOR:-$CAMUNDA_REGION_SLOTS}"
echo "    surviving regions    : $surviving_regions of $CAMUNDA_ACTIVE_REGIONS"

if [ "$surviving_regions" -le $((CAMUNDA_ACTIVE_REGIONS / 2)) ]; then
    echo
    echo "WARNING: with $surviving_regions of $CAMUNDA_ACTIVE_REGIONS regions left, partitions no longer hold a" >&2
    echo "         majority of their replicas and Zeebe has stopped processing. Recovery" >&2
    echo "         requires force-removing the lost brokers; re-run with --drain-brokers." >&2
else
    echo "    Partitions keep a majority of their replicas: Zeebe keeps processing."
fi

echo
echo "--> Current cluster view"
camunda::management "$survivor_context" GET /actuator/cluster | jq '{lastChange, brokers: [.brokers[]?.id]}'

###############################################################################
# 2. Database writer                                                          #
###############################################################################

if [ -z "${AURORA_GLOBAL_CLUSTER_ID:-}" ]; then
    echo
    echo "--> Database: AURORA_GLOBAL_CLUSTER_ID is not set, skipping."
    echo "    Bring-your-own RDBMS: promote a surviving replica with your own tooling."
    echo "    Camunda needs no reconfiguration as long as the JDBC URL keeps resolving"
    echo "    to the current writer."
else
    echo
    echo "--> Database: inspecting the Aurora Global Database $AURORA_GLOBAL_CLUSTER_ID"

    members_json="$(aws rds describe-global-clusters \
        --global-cluster-identifier "$AURORA_GLOBAL_CLUSTER_ID" \
        --query 'GlobalClusters[0].GlobalClusterMembers' --output json)"

    writer_arn="$(echo "$members_json" | jq -r '.[] | select(.IsWriter == true) | .DBClusterArn')"
    writer_region="$(echo "$writer_arn" | cut -d: -f4)"
    lost_region="${aws_regions[$LOST_SLOT]}"

    echo "    current writer region: $writer_region"

    if [ "$writer_region" != "$lost_region" ]; then
        echo "    The writer is not in the lost region: no database action required."
    else
        target_arn="$(echo "$members_json" | jq -r --arg lost "$lost_region" \
            '[.[] | select(.IsWriter != true) | select((.DBClusterArn | split(":")[3]) != $lost)][0].DBClusterArn')"

        if [ -z "$target_arn" ] || [ "$target_arn" = "null" ]; then
            echo "ERROR: no surviving Aurora member to promote." >&2
            exit 1
        fi

        if [ "$UNPLANNED" = true ]; then
            echo "    Unplanned: detaching and promoting $target_arn"
            echo "    Data not yet replicated at the time of the outage is lost."
            aws rds remove-from-global-cluster \
                --global-cluster-identifier "$AURORA_GLOBAL_CLUSTER_ID" \
                --db-cluster-identifier "$target_arn"
        else
            echo "    Planned switchover to $target_arn"
            aws rds failover-global-cluster \
                --global-cluster-identifier "$AURORA_GLOBAL_CLUSTER_ID" \
                --target-db-cluster-identifier "$target_arn"
        fi

        echo "    Waiting for the promoted cluster to become available ..."
        target_id="$(basename "$target_arn")"
        target_region="$(echo "$target_arn" | cut -d: -f4)"
        aws rds wait db-cluster-available \
            --region "$target_region" \
            --db-cluster-identifier "$target_id"

        echo "    Promotion complete."
        echo
        echo "    The AWS Advanced JDBC Wrapper failover plugin discovers the new writer"
        echo "    from globalClusterInstanceHostPatterns, so Camunda needs no restart."
        echo "    Connections in flight during the promotion are retried by the driver."
    fi
fi

###############################################################################
# 3. Optional: drain the lost brokers                                         #
###############################################################################

if [ "$DRAIN_BROKERS" = true ]; then
    node_ids="$(camunda::region_node_ids "$LOST_SLOT")"
    echo
    echo "--> Removing the brokers of region slot $LOST_SLOT: $node_ids"
    echo "    force=true is required because the brokers are unreachable. It reduces"
    echo "    the replication factor of the affected partitions instead of moving"
    echo "    their replicas."

    remove_json="$(printf '%s\n' "$node_ids" | tr ' ' '\n' | jq -R . | jq -sc .)"
    body="$(jq -nc --argjson remove "$remove_json" '{brokers: {remove: $remove}}')"

    camunda::management "$survivor_context" PATCH "/actuator/cluster?force=true" "$body"
    camunda::wait_for_cluster_change "$survivor_context"
fi

echo
echo "==============================================================="
echo " Failover complete."
echo
echo " Next steps:"
echo "   * Route client traffic away from region slot $LOST_SLOT."
echo "   * Run ./check-cluster-topology.sh to confirm the degraded but healthy state."
echo "   * When the region is back, run ./failback.sh $LOST_SLOT."
echo "==============================================================="

#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Handles the loss of one region.
#
#   ./failover.sh <lost-region-slot> [--unplanned] [--drain-brokers] [--dry-run]
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
# `--drain-brokers` additionally force-removes the lost zone from the Zeebe
# cluster, through `DELETE /actuator/cluster/zones/<zone>`. That is one atomic
# change: the zone's brokers are evicted and the zone leaves the persisted
# partition distribution, so quorum stops counting replicas that cannot answer.
#
# Whether you need it depends on how many zones are left. Two zones lose their
# majority when one goes, and processing only resumes once the zone is removed.
# Three or more keep a majority without it, and a zone expected back is cheaper
# left in place: its brokers catch up from the Raft log, where a removed zone has
# to be added back explicitly. See "Region loss" in ../README.md.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${AWS_REGIONS:?AWS_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"

if [ $# -lt 1 ]; then
    echo "usage: $0 <lost-region-slot> [--unplanned] [--drain-brokers] [--dry-run]" >&2
    exit 1
fi

LOST_SLOT="$1"
shift
UNPLANNED=false
DRAIN_BROKERS=false
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
    --unplanned) UNPLANNED=true ;;
    --drain-brokers) DRAIN_BROKERS=true ;;
    --dry-run) DRY_RUN=true ;;
    *)
        echo "unknown argument: $arg" >&2
        exit 1
        ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-management-api.sh"

read -r -a aws_regions <<<"$AWS_REGIONS"

survivor_context="$(camunda::survivor_context "$LOST_SLOT")"
camunda::use_surviving_region "$LOST_SLOT"

echo "==============================================================="
echo " Region slot $LOST_SLOT (${aws_regions[$LOST_SLOT]}) declared lost"
echo " Driving the procedure from $survivor_context"
echo "==============================================================="

###############################################################################
# 1. Zeebe: report, do not act                                                #
###############################################################################

surviving_regions=$((CAMUNDA_ACTIVE_REGIONS - 1))
echo
echo "--> Zeebe quorum check"
echo "    replicationFactor    : ${CAMUNDA_REPLICATION_FACTOR:-$CAMUNDA_REGION_SLOTS}"
echo "    surviving regions    : $surviving_regions of $CAMUNDA_ACTIVE_REGIONS"

# Quorum is a majority of the REPLICAS, and there is one replica per slot,
# deployed or not. Comparing against the active count instead reads a four-slot
# cluster running three regions as healthy after losing one: two survivors beat
# half of three, but two replicas of four is not a majority, and the engine has
# stopped. Telling an operator otherwise during an incident is the worst moment
# to be optimistic.
if [ "$((2 * surviving_regions))" -le "$CAMUNDA_REGION_SLOTS" ]; then
    echo
    echo "WARNING: with $surviving_regions regions left of $CAMUNDA_REGION_SLOTS replicas, partitions no longer" >&2
    echo "         hold a majority and Zeebe has stopped processing. Recovery" >&2
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

        if [ "$DRY_RUN" = true ]; then
            echo "    --dry-run: would promote $target_arn, doing nothing."
        else
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
fi

###############################################################################
# 3. Optional: force-remove the lost zone                                     #
###############################################################################

if [ "$DRAIN_BROKERS" = true ]; then
    lost_zone="$(camunda::zone_name "$LOST_SLOT")"

    echo
    echo "--> Force-removing zone $lost_zone"
    echo "    One atomic change evicts the zone's brokers and drops the zone from the"
    echo "    persisted partition distribution, so the surviving zones become the whole"
    echo "    cluster: the affected partitions lose a replica rather than waiting for"
    echo "    one that cannot answer, and quorum is computed without it."
    echo "    Only do this for a zone that is down and unreachable."

    if [ "$DRY_RUN" = true ]; then
        echo "    --dry-run: asking the API for the plan, changing nothing."
        camunda::management "$survivor_context" \
            DELETE "/actuator/cluster/zones/${lost_zone}?dryRun=true" |
            jq '{plannedChanges, expectedBrokers: [.expectedTopology[]?.id]}'
    else
        camunda::management "$survivor_context" DELETE "/actuator/cluster/zones/$lost_zone"
        camunda::wait_for_cluster_change "$survivor_context"
    fi
fi

if [ "$DRY_RUN" = true ]; then
    echo
    echo "--> --dry-run: nothing was changed, so there is no degraded state to verify."
    exit 0
fi

echo
echo "--> Verifying the degraded cluster"
"$SCRIPT_DIR/verify-degraded-cluster.sh" "$LOST_SLOT"

echo
echo "==============================================================="
echo " Failover complete."
echo
echo " Next steps:"
echo "   * Route client traffic away from region slot $LOST_SLOT."
echo "   * When the region is back, run ./failback.sh $LOST_SLOT."
echo "==============================================================="

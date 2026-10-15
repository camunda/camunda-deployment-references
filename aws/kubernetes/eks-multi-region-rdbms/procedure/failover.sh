#!/usr/bin/env bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Handles the loss of one region.
#
#   ./failover.sh <lost-region-slot> [--drain-brokers] [--keep-writer] [--dry-run]
#
# With at least three zones and a layout where no single zone holds half the
# replicas, losing one region leaves every partition with a majority of its
# replicas: Zeebe keeps processing and NO Zeebe action is required. The default
# 2-2-1 satisfies that -- losing a database zone leaves 3 of 5, losing the
# tie-breaker leaves 4 of 5. That is the entire point of this topology, and the
# difference with the dual-region architecture, where a region loss halts the
# cluster until brokers are force-removed.
#
# What still needs attention is the database, because Aurora Global Database has
# a single writer region:
#
#   * If the writer was NOT in the lost region, nothing to do.
#   * Planned (region still reachable): `failover-global-cluster` performs a
#     switchover with no data loss. It needs the old writer to be `available`;
#     the script checks that first.
# An unplanned Aurora Global Database failover is not automated here: detaching
# a member changes topology outside Terraform, and this module deliberately
# ignores that membership field. Follow the AWS recovery procedure instead.
# When the lost region's Aurora is down too, pass `--keep-writer` to skip the
# switchover and still run the Zeebe steps.
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
# to be added back explicitly.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${AWS_REGIONS:?AWS_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"

if [ $# -lt 1 ]; then
    echo "usage: $0 <lost-region-slot> [--drain-brokers] [--keep-writer] [--dry-run]" >&2
    exit 1
fi

LOST_SLOT="$1"
shift
DRAIN_BROKERS=false
KEEP_WRITER=false
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
    --drain-brokers) DRAIN_BROKERS=true ;;
    --keep-writer) KEEP_WRITER=true ;;
    --dry-run) DRY_RUN=true ;;
    *)
        echo "unknown argument: $arg" >&2
        exit 1
        ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-management-api.sh"
# shellcheck source=SCRIPTDIR/aurora.sh
. "$SCRIPT_DIR/aurora.sh"

read -r -a aws_regions <<<"$AWS_REGIONS"

aurora_unplanned_hint() {
    echo "Follow the Aurora Global Database unplanned recovery procedure:" >&2
    echo "  https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html" >&2
    echo "Zeebe keeps processing; exporting waits until a writer is available." >&2
    echo "When the Aurora primary is down as well, rerun with --keep-writer to finish the other steps." >&2
}

camunda::require_slot "$LOST_SLOT" "the lost region slot"

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

# Quorum is a majority of the REPLICAS, and a zone does not necessarily hold
# one: the default layout puts 2 in each database zone and 1 in the tie-breaker.
# Counting zones instead would misreport both ways -- losing the tie-breaker of
# a 2-2-1 cluster leaves 4 replicas of 5 and is fine, losing a database zone
# leaves 3 of 5 and is also fine, but a 4-1-1 layout losing its big zone leaves
# 2 of 6 and is not. Only the replicas answer it, so they are what is summed.
read -r -a _zone_replicas <<<"${CAMUNDA_ZONE_REPLICAS:?CAMUNDA_ZONE_REPLICAS must be set, source export_environment_prerequisites.sh}"
surviving_replicas=0
for ((_i = 0; _i < CAMUNDA_ACTIVE_REGIONS; _i++)); do
    [ "$_i" -eq "$LOST_SLOT" ] && continue
    surviving_replicas=$((surviving_replicas + _zone_replicas[_i]))
done

echo
echo "--> Zeebe quorum check"
echo "    zone replicas        : $CAMUNDA_ZONE_REPLICAS"
echo "    replicationFactor    : $CAMUNDA_REPLICATION_FACTOR"
echo "    surviving regions    : $surviving_regions of $CAMUNDA_ACTIVE_REGIONS"
echo "    surviving replicas   : $surviving_replicas of $CAMUNDA_REPLICATION_FACTOR"

if [ "$((2 * surviving_replicas))" -le "$CAMUNDA_REPLICATION_FACTOR" ]; then
    echo
    echo "WARNING: with $surviving_replicas replicas left of $CAMUNDA_REPLICATION_FACTOR, partitions no longer" >&2
    echo "         hold a majority and Zeebe has stopped processing. Recovery" >&2
    echo "         requires force-removing the lost brokers; re-run with --drain-brokers." >&2
else
    echo "    Partitions keep a majority of their replicas: Zeebe keeps processing."
fi

echo
echo "--> Current cluster view"
if cluster_view="$(camunda::management "$survivor_context" GET /actuator/cluster 2>/dev/null)"; then
    echo "$cluster_view" | jq '{lastChange, brokers: [.brokers[]?.id]}'
else
    echo "    unavailable while the lost coordinator leaves the cluster; continuing with the quorum verified above."
fi

###############################################################################
# 2. Database writer                                                          #
###############################################################################

if [ -z "${AURORA_GLOBAL_CLUSTER_ID:-}" ]; then
    echo
    echo "--> Database: AURORA_GLOBAL_CLUSTER_ID is not set, skipping."
    echo "    Bring-your-own RDBMS: promote a surviving replica with your own tooling."
    echo "    Camunda needs no reconfiguration as long as the JDBC URL keeps resolving"
    echo "    to the current writer."
elif [ "$KEEP_WRITER" = true ]; then
    echo
    echo "--> Database: --keep-writer given, leaving the Aurora writer where it is."
    echo "    If it was in ${aws_regions[$LOST_SLOT]}, recover it with the Aurora Global Database"
    echo "    unplanned recovery procedure; exporting waits until a writer is available."
else
    echo
    echo "--> Database: inspecting the Aurora Global Database $AURORA_GLOBAL_CLUSTER_ID"

    # A rerun can find the previous run's switchover still going: decide from
    # the settled membership, never start a second switchover.
    lost_region="${aws_regions[$LOST_SLOT]}"
    surviving_region="${aws_regions[$((LOST_SLOT == 0 ? 1 : 0))]}"
    if ! global_json="$(aurora_settled_global "$surviving_region")"; then
        echo "ERROR: could not read a settled Aurora global cluster." >&2
        exit 1
    fi
    members_json="$(echo "$global_json" | jq '.GlobalClusterMembers')"

    writer_arn="$(echo "$members_json" | jq -r '.[] | select(.IsWriter == true) | .DBClusterArn')"
    if [ -z "$writer_arn" ]; then
        echo "ERROR: No Aurora writer ARN in the global cluster." >&2
        exit 1
    fi
    writer_region="$(echo "$writer_arn" | cut -d: -f4)"

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
            # A planned switchover needs the current primary to be healthy. If
            # the lost region's Aurora cluster is down too, only AWS's unplanned
            # recovery can move the writer, and that can lose data.
            writer_status="$(aws rds describe-db-clusters --region "$lost_region" \
                --db-cluster-identifier "$writer_arn" \
                --query 'DBClusters[0].Status' --output text 2>/dev/null || echo unreachable)"
            if [ "$writer_status" != "available" ]; then
                echo "ERROR: the Aurora writer in $lost_region is $writer_status, so a planned switchover cannot run." >&2
                aurora_unplanned_hint
                exit 1
            fi

            echo "    Planned switchover to $target_arn"
            # The status read above can still say "available" early in an
            # outage: a rejected or stalled switchover gets the same guidance.
            # Exit code 2 means a rerun finishes the move (the helper says so).
            rc=0
            aurora_switch_to "$target_arn" || rc=$?
            if [ "$rc" -ne 0 ]; then
                echo "ERROR: the planned switchover to $target_arn did not complete." >&2
                [ "$rc" -eq 2 ] || aurora_unplanned_hint
                exit "$rc"
            fi

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
            DELETE "/actuator/cluster/zones/${lost_zone}?force=true&dryRun=true" |
            jq '{plannedChanges, expectedBrokers: [.expectedTopology[]?.id]}'
    else
        response="$(camunda::management "$survivor_context" DELETE "/actuator/cluster/zones/${lost_zone}?force=true")"
        echo "$response"
        camunda::wait_for_cluster_change "$survivor_context" "$(echo "$response" | jq -r '.changeId // .pendingChange.id // empty')"
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

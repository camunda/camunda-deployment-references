#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Brings a recovered region back into the cluster.
#
#   ./failback.sh <recovered-region-slot> [--switch-writer]
#
# Compared with the dual-region procedure this is short, and deliberately so.
# There is no secondary-storage snapshot and restore step: the RDBMS holds a
# single copy of the exported data, replicated by the database itself, so a
# region coming back has nothing to catch up on at the Camunda level. The Zeebe
# brokers replay their Raft log from the surviving replicas exactly as they
# would after a node restart.
#
# `--switch-writer` moves the Aurora writer back to the recovered region. It is
# optional: leaving the writer where it is costs nothing but cross-region
# latency for the regions further away from it.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${AWS_REGIONS:?AWS_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"

if [ $# -lt 1 ]; then
    echo "usage: $0 <recovered-region-slot> [--switch-writer]" >&2
    exit 1
fi

RECOVERED_SLOT="$1"
shift
SWITCH_WRITER=false
for arg in "$@"; do
    case "$arg" in
    --switch-writer) SWITCH_WRITER=true ;;
    *)
        echo "unknown argument: $arg" >&2
        exit 1
        ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-management-api.sh"

read -r -a aws_regions <<<"$AWS_REGIONS"

survivor_context="$(camunda::survivor_context "$RECOVERED_SLOT")"
recovered_zone="$(camunda::zone_name "$RECOVERED_SLOT")"

echo "==============================================================="
echo " Failback of region slot $RECOVERED_SLOT (${aws_regions[$RECOVERED_SLOT]})"
echo "==============================================================="

###############################################################################
# 1. Redeploy Camunda in the recovered region                                 #
###############################################################################

echo
echo "--> 1/4 Redeploying Camunda in region slot $RECOVERED_SLOT"

"$SCRIPT_DIR/setup-namespaces.sh"
"$SCRIPT_DIR/create-rdbms-secret.sh"

. "$SCRIPT_DIR/generate-zeebe-helm-values.sh"
"$SCRIPT_DIR/assemble-envsubst-values.sh"
"$SCRIPT_DIR/install-chart.sh" "$RECOVERED_SLOT"

echo
echo "--> 2/4 Re-exporting the region's services to the ClusterSet"
"$SCRIPT_DIR/submariner/export-services.sh"

###############################################################################
# 2. Re-add the zone if it was force-removed                                  #
###############################################################################

echo
echo "--> 3/4 Checking whether zone $recovered_zone is still in the partition distribution"

cluster="$(camunda::management "$survivor_context" GET /actuator/cluster)"

if echo "$cluster" | jq -e --arg zone "$recovered_zone" \
    '[.partitionDistribution.zones[]? | select(.name == $zone)] | length > 0' >/dev/null; then
    echo "    Zone $recovered_zone was never removed; its brokers rejoin and catch up"
    echo "    from the Raft log without any membership change."
else
    echo "    Zone $recovered_zone was force-removed during failover; adding it back."

    # The zone is gone from the cluster, so its replica count and priority cannot
    # be read back from there. They come from the zone list that step 1 rendered,
    # which is also the one the chart just deployed, so the two cannot drift.
    zone_spec="$(echo "$CAMUNDA_MULTIREGION_ZONES" | jq -c --arg zone "$recovered_zone" \
        '.[] | select(.name == $zone)')"
    if [ -z "$zone_spec" ]; then
        echo "ERROR: zone $recovered_zone is not in CAMUNDA_MULTIREGION_ZONES." >&2
        exit 1
    fi

    # Zone-aware broker IDs, which is what the API expects: after the removal
    # there is no membership left to read them from.
    brokers_json="$(camunda::region_node_ids "$RECOVERED_SLOT" | tr ' ' '\n' | jq -R . | jq -sc .)"
    body="$(echo "$zone_spec" | jq -c --argjson brokers "$brokers_json" \
        '{numberOfReplicas, priority, brokers: $brokers}')"

    echo "    POST /actuator/cluster/zones/$recovered_zone $body"
    camunda::management "$survivor_context" POST "/actuator/cluster/zones/$recovered_zone" "$body"
    camunda::wait_for_cluster_change "$survivor_context"
fi

###############################################################################
# 3. Database                                                                 #
###############################################################################

echo
echo "--> 4/4 Database"

if [ -z "${AURORA_GLOBAL_CLUSTER_ID:-}" ]; then
    echo "    AURORA_GLOBAL_CLUSTER_ID is not set, skipping."
else
    members_json="$(aws rds describe-global-clusters \
        --global-cluster-identifier "$AURORA_GLOBAL_CLUSTER_ID" \
        --query 'GlobalClusters[0].GlobalClusterMembers' --output json 2>/dev/null || echo '[]')"

    member_count="$(echo "$members_json" | jq 'length')"
    echo "    Global cluster members: $member_count"

    if [ "$member_count" -le 1 ]; then
        echo
        echo "    The global cluster has a single member, which means failover ran with"
        echo "    --unplanned and detached it. Rebuilding the global topology is a"
        echo "    Terraform operation, not a script one: re-run"
        echo
        echo "        terraform apply"
        echo
        echo "    in terraform/clusters so the missing Aurora members are recreated and"
        echo "    re-attached, then re-run this script if you also want --switch-writer."
    elif [ "$SWITCH_WRITER" = true ]; then
        recovered_region="${aws_regions[$RECOVERED_SLOT]}"
        target_arn="$(echo "$members_json" | jq -r --arg region "$recovered_region" \
            '[.[] | select((.DBClusterArn | split(":")[3]) == $region)][0].DBClusterArn')"

        if [ -z "$target_arn" ] || [ "$target_arn" = "null" ]; then
            echo "    No Aurora member in $recovered_region, nothing to switch back to."
        else
            echo "    Switching the writer back to $target_arn"
            aws rds failover-global-cluster \
                --global-cluster-identifier "$AURORA_GLOBAL_CLUSTER_ID" \
                --target-db-cluster-identifier "$target_arn"

            target_id="$(basename "$target_arn")"
            aws rds wait db-cluster-available \
                --region "$recovered_region" \
                --db-cluster-identifier "$target_id"
            echo "    Writer is back in $recovered_region."
        fi
    else
        writer_region="$(echo "$members_json" | jq -r '.[] | select(.IsWriter == true) | .DBClusterArn' | cut -d: -f4)"
        echo "    Writer stays in $writer_region. Pass --switch-writer to move it back."
    fi
fi

echo
echo "==============================================================="
echo " Failback complete. Verifying the topology:"
echo "==============================================================="
"$SCRIPT_DIR/check-cluster-topology.sh"

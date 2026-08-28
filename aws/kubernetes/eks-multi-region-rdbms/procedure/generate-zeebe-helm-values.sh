#!/bin/bash
set -euo pipefail

# Emits the region-dependent Camunda settings that cannot be hardcoded in the
# Helm values, then exports them so that assemble-envsubst-values.sh can
# substitute them.
#
# Three values are produced:
#
#   CAMUNDA_CLUSTER_INITIALCONTACTPOINTS
#       One entry per ACTIVE region, pointing at the headless Zeebe service of
#       that region through Submariner Lighthouse. Zeebe resolves a headless
#       clusterset name to every broker pod IP of the exporting cluster, so the
#       list stays independent of the number of brokers per region.
#
#   REGION_<slot>_ZEEBE_SERVICE_NAME
#       Suffix of the advertised host of each broker. The chart default
#       (`<pod>.<service>.<namespace>.svc`) only resolves inside its own
#       cluster.
#
#   CAMUNDA_MULTIREGION_ZONES
#       The `global.multiregion.zones` list, as a JSON flow sequence. Covers the
#       DEPLOYED zones only -- see the note below on why listing an absent one
#       stalls the cluster -- and is byte-identical in every region's values
#       file, which is what keeps the topology a single description.
#
# Contact points intentionally cover only the active regions: a slot that has
# not been deployed yet has no DNS record, and listing it would make every
# broker wait on the startup DNS gate for nothing.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"

: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ZONE_NAMES:?CAMUNDA_ZONE_NAMES must be set, source export-terraform-outputs.sh}"

INTERNAL_PORT="${CAMUNDA_CLUSTER_INTERNAL_PORT:-26502}"

# Replicas of each partition placed in a single zone. One per zone means the
# replication factor equals the zone count, so every zone holds exactly one
# replica of every partition and losing a zone costs one replica out of N.
ZONE_REPLICAS="${CAMUNDA_REPLICAS_PER_ZONE:-1}"

# Raft election priority of zone 0, decreasing by this step per zone. Leaders
# are skewed to zone 0 because it hosts the Aurora writer: a leader co-located
# with the writer avoids the inter-region round trip on every export flush,
# which is the cost measured by ./measure-rdbms-latency.sh.
ZONE_PRIORITY_BASE="${CAMUNDA_ZONE_PRIORITY_BASE:-1000}"
ZONE_PRIORITY_STEP="${CAMUNDA_ZONE_PRIORITY_STEP:-100}"

read -r -a cluster_ids <<<"$SUBMARINER_CLUSTER_IDS"
# Every slot, including ones not deployed yet. SUBMARINER_CLUSTER_IDS covers the
# ACTIVE regions only -- it names the clusters joined to the ClusterSet -- so
# using it here builds a zone list one entry short and quietly drops the growth
# property.
read -r -a zone_names <<<"$CAMUNDA_ZONE_NAMES"

contact_points=""
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    # Trailing dot: this is a fully-qualified name, and saying so matters.
    #
    # Without it the resolver walks the pod's search domains first, and on a
    # cold multi-region start a broker whose peer is not yet published spends
    # its DNS budget on those attempts, parks during startup and never binds
    # 9600 -- permanently, the pod has to be deleted to recover. That is
    # camunda/camunda#55038, which upstream closed as fixed downstream: the fix
    # is exactly this dot, applied to the dual-region references in #2793 and
    # never carried over here.
    #
    # The cross-region DNS gate in ../helm-values/camunda-values.yml derives its
    # per-pod hostnames from these contact points, so it inherits the dot too.
    fqdn="${cluster_ids[$i]}.${CAMUNDA_RELEASE_NAME}-zeebe.${CAMUNDA_NAMESPACE}.svc.clusterset.local."

    export "REGION_${i}_ZEEBE_SERVICE_NAME=$fqdn"

    if [ -z "$contact_points" ]; then
        contact_points="${fqdn}:${INTERNAL_PORT}"
    else
        contact_points="${contact_points},${fqdn}:${INTERNAL_PORT}"
    fi
done

export CAMUNDA_CLUSTER_INITIALCONTACTPOINTS="$contact_points"

###############################################################################
# Zone list                                                                   #
#                                                                             #
# Only DEPLOYED zones are listed. Listing a zone that does not exist yet was   #
# assumed to reserve its replicas and leave each partition running at N-1 of   #
# N -- a majority, so a working cluster. That is not what happens: the cluster #
# stalls configuring partitions on the absent member and never converges.      #
#                                                                             #
#   Expected to send a message with subject 'default-partition-1-configure'    #
#   to member 'zurich_0', but member is not known.                             #
#                                                                             #
# Growth therefore means EXTENDING this list when a zone is activated, and     #
# telling the RUNNING cluster about it: rendering the longer list only reaches #
# the region being installed. ./activate-region.sh does the first half and not #
# yet the second: it has no POST /actuator/cluster/zones/<zone>, so a newly    #
# activated zone stays unknown to the regions already up. failback.sh already  #
# carries the primitive that closes this. Until it lands, the growth test      #
# TestMultiRegionActivateRegion is expected to fail, which is the other reason #
# active_region_count now defaults to every slot: the growth path becomes      #
# opt-in instead of sitting on the way to every other scenario.                #
#                                                                             #
# The direction matches how the zone-aware documentation frames it: zones are  #
# added dynamically, rather than pre-declared and filled in.                   #
#                                                                             #
# Emitted as JSON so that ../helm-values/camunda-values.yml stays valid YAML   #
# as a template, rather than only after substitution.                          #
###############################################################################

zones_json=""
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    zone_name="${zone_names[$i]:-}"
    if [ -z "$zone_name" ]; then
        echo "ERROR: CAMUNDA_ZONE_NAMES has no entry for zone slot $i." >&2
        echo "       It must name every one of the $CAMUNDA_REGION_SLOTS slots, not only the active ones." >&2
        echo "       It comes from the zone_names Terraform output; re-source export-terraform-outputs.sh." >&2
        exit 1
    fi

    entry="$(printf '{"name":"%s","numberOfBrokers":%d,"numberOfReplicas":%d,"priority":%d}' \
        "$zone_name" "$CAMUNDA_BROKERS_PER_REGION" "$ZONE_REPLICAS" \
        "$((ZONE_PRIORITY_BASE - i * ZONE_PRIORITY_STEP))")"

    zones_json="${zones_json:+$zones_json,}${entry}"
done

# A JSON array is a YAML flow sequence, so the values template stays valid YAML
# before envsubst runs and can be linted like any other file.
export CAMUNDA_MULTIREGION_ZONES="[${zones_json}]"

echo "CAMUNDA_CLUSTER_INITIALCONTACTPOINTS=$CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
echo "CAMUNDA_MULTIREGION_ZONES=$CAMUNDA_MULTIREGION_ZONES"
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    varname="REGION_${i}_ZEEBE_SERVICE_NAME"
    echo "${varname}=${!varname}"
done

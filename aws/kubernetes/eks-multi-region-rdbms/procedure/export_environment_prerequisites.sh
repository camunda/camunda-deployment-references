#!/usr/bin/env bash
# shellcheck disable=SC2155
# The file is meant to be SOURCED, so it ends with `return`; when it is executed
# directly `return` fails and `exit` takes over. shellcheck only sees the first
# branch and reports the second as unreachable.
# shellcheck disable=SC2317
# Environment contract of the AWS EKS multi-region RDBMS reference architecture.
#
# Source this file before running any other procedure:
#
#   . ./export_environment_prerequisites.sh
#
# Every value can be overridden by exporting it beforehand. Region-indexed
# values are space-separated lists whose order matches the region SLOT order of
# the Terraform `regions` variable; index 0 is region slot 0.

set -o pipefail

###############################################################################
# Region topology                                                             #
###############################################################################

# Number of REGION SLOTS provisioned by Terraform. A slot is infrastructure that
# can host a zone; it is not a zone until Camunda runs in it. A broker's own ID
# is its index INSIDE its zone, so the slot count does not enter into it.
export CAMUNDA_REGION_SLOTS="${CAMUNDA_REGION_SLOTS:-3}"

# Number of slots running Camunda, and therefore the number of zones the cluster
# declares. Only deployed zones are declared: a declared zone without running
# brokers still receives replicas, and every partition then runs one zone short.
# A slot is added later through activate-region.sh, which adds its zone with the
# cluster management API.
export CAMUNDA_ACTIVE_REGIONS="${CAMUNDA_ACTIVE_REGIONS:-3}"

# AWS regions, kubectl contexts and Submariner cluster IDs, one entry per slot.
# The Submariner cluster ID becomes the first DNS label of every cross-cluster
# name (<clusterID>.<service>.<namespace>.svc.clusterset.local) and must be a
# valid DNS-1123 label.
export AWS_REGIONS="${AWS_REGIONS:-eu-west-2 eu-west-3 eu-central-2}"
export CLUSTER_CONTEXTS="${CLUSTER_CONTEXTS:-cluster-london cluster-paris cluster-zurich}"
export SUBMARINER_CLUSTER_IDS="${SUBMARINER_CLUSTER_IDS:-london paris zurich}"

# Slot hosting the Submariner broker. Any cluster can host it; the broker only
# stores metadata. Losing it stops NEW service exports from propagating, and
# leaves the records already published in place. There is no data plane to
# interrupt: Submariner runs here for service discovery only and the Transit
# Gateway carries the traffic.
export SUBMARINER_BROKER_SLOT="${SUBMARINER_BROKER_SLOT:-0}"

###############################################################################
# Camunda topology                                                            #
###############################################################################

# A single namespace name is reused in every cluster. Submariner Lighthouse
# disambiguates identically named services with the cluster ID prefix, so
# unlike the dual-region CoreDNS-chaining setup there is no need for one
# namespace per region.
export CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
export CAMUNDA_RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"

export CAMUNDA_BROKERS_PER_REGION="${CAMUNDA_BROKERS_PER_REGION:-2}"
export CAMUNDA_CLUSTER_SIZE="${CAMUNDA_CLUSTER_SIZE:-$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_ACTIVE_REGIONS))}"
# Sized on the slots rather than on the running zones, so the count already
# fits the largest topology. Adding a zone only adds replicas. Raising the count
# later takes partition scaling, which cannot run during the same change.
export CAMUNDA_PARTITION_COUNT="${CAMUNDA_PARTITION_COUNT:-$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_REGION_SLOTS))}"

# Replicas of every partition placed in each zone, one entry per slot.
#
# The default is 2 in the first two zones and 1 in the rest, so three slots give
# 2-2-1 at replicationFactor 5. The single-replica zone is the tie-breaker: with
# `database_region_slots = [0, 1]` it is also the zone with no Aurora member, so
# it carries a vote without carrying a database. Losing either database zone
# still leaves 3 replicas of 5.
#
# This is a default, not a constraint. Any layout the chart accepts works --
# uniform 1-1-1, 3-3-3, or an asymmetric one -- as long as every zone has at
# least one replica and no zone has more replicas than it has brokers. Both are
# checked below.
#
#   export CAMUNDA_ZONE_REPLICAS="2 2 1"
if [ -z "${CAMUNDA_ZONE_REPLICAS:-}" ]; then
    _zone_replicas=""
    for ((_i = 0; _i < CAMUNDA_REGION_SLOTS; _i++)); do
        if [ "$_i" -lt 2 ]; then
            _zone_replicas="${_zone_replicas:+$_zone_replicas }2"
        else
            _zone_replicas="${_zone_replicas:+$_zone_replicas }1"
        fi
    done
    CAMUNDA_ZONE_REPLICAS="$_zone_replicas"
    unset _i _zone_replicas
fi
export CAMUNDA_ZONE_REPLICAS

# Consume the rolling chart from the camunda-platform-helm main branch, like the
# other architectures. The pin below is a commit on that branch, bumped by
# Renovate as main moves; zone awareness is in no released chart, so a tag pin
# cannot carry `orchestration.partitioning.scheme: zone-aware`.
#
# Hand-assembling CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_* against a released
# chart is not an alternative: that chart derives the node ID from `regions` and
# `regionId`, which is the arithmetic zone awareness replaces, and no value
# passed from outside overrides it -- `${VAR:-default}` treats an empty value as
# unset. See camunda/camunda-platform-helm#6807.
#
# renovate-helm-main: digest tracked against camunda-platform-helm main
export CAMUNDA_HELM_CHART_GIT_REF="${CAMUNDA_HELM_CHART_GIT_REF:-a5ee96e435b83c3964552d94788fe1765e152b5a}"

# TODO: [release-duty] drop the source build and switch HELM_CHART_REF to
# https://helm.camunda.io once 8.10 is generally available.
# renovate: datasource=helm depName=camunda-platform versioning=regex:^15(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io renovate-inert-ok
export HELM_CHART_VERSION="${HELM_CHART_VERSION:-15-dev-latest}"
export HELM_CHART_REF="${HELM_CHART_REF:-oci://registry.camunda.cloud/team-distribution/camunda-platform}"

###############################################################################
# Secondary storage                                                           #
###############################################################################

# Single JDBC URL shared by every broker of every region. Camunda has no
# multi-region RDBMS mode: replication and writer failover are delegated to the
# database. Populate it from Terraform with:
#
#   export CAMUNDA_RDBMS_URL="$(terraform -chdir=../terraform/clusters output -raw camunda_rdbms_url)"
export CAMUNDA_RDBMS_URL="${CAMUNDA_RDBMS_URL:-}"
export CAMUNDA_RDBMS_USERNAME="${CAMUNDA_RDBMS_USERNAME:-camunda}"
export CAMUNDA_RDBMS_PASSWORD="${CAMUNDA_RDBMS_PASSWORD:-}"

# Aurora Global Database identifier, used by failover.sh and failback.sh. Left
# empty when bringing your own RDBMS.
export AURORA_GLOBAL_CLUSTER_ID="${AURORA_GLOBAL_CLUSTER_ID:-}"

###############################################################################
# Orchestration Cluster credentials                                           #
###############################################################################

# Basic-auth user the procedures authenticate the v2 API with. It has to match a
# user the chart provisions.
#
# There is deliberately no default. The chart's demo/demo admin login is what
# caused INC-5340 on publicly reachable deployments, so an unset value has to
# stop the procedure rather than silently reach for it.
export CAMUNDA_BASIC_AUTH_USER="${CAMUNDA_BASIC_AUTH_USER:-}"
export CAMUNDA_BASIC_AUTH_PASSWORD="${CAMUNDA_BASIC_AUTH_PASSWORD:-}"

###############################################################################
# Consistency checks                                                          #
###############################################################################

_multiregion_count() { echo "$#"; }

# Word splitting is intentional here: the region lists are space-separated.
# shellcheck disable=SC2086
_aws_region_count="$(_multiregion_count $AWS_REGIONS)"
# shellcheck disable=SC2086
_context_count="$(_multiregion_count $CLUSTER_CONTEXTS)"
# shellcheck disable=SC2086
_submariner_id_count="$(_multiregion_count $SUBMARINER_CLUSTER_IDS)"

if [ "$_aws_region_count" -lt "$CAMUNDA_ACTIVE_REGIONS" ] ||
    [ "$_context_count" -lt "$CAMUNDA_ACTIVE_REGIONS" ] ||
    [ "$_submariner_id_count" -lt "$CAMUNDA_ACTIVE_REGIONS" ]; then
    echo "ERROR: AWS_REGIONS, CLUSTER_CONTEXTS and SUBMARINER_CLUSTER_IDS must each list at least CAMUNDA_ACTIVE_REGIONS ($CAMUNDA_ACTIVE_REGIONS) entries." >&2
    return 1 2>/dev/null || exit 1
fi

if [ "$CAMUNDA_ACTIVE_REGIONS" -gt "$CAMUNDA_REGION_SLOTS" ]; then
    echo "ERROR: CAMUNDA_ACTIVE_REGIONS ($CAMUNDA_ACTIVE_REGIONS) exceeds CAMUNDA_REGION_SLOTS ($CAMUNDA_REGION_SLOTS)." >&2
    return 1 2>/dev/null || exit 1
fi

# The zone replica layout is the one place an asymmetric topology can go wrong
# silently, so it is validated rather than trusted.
# shellcheck disable=SC2086
_zone_replica_count="$(_multiregion_count $CAMUNDA_ZONE_REPLICAS)"

if [ "$_zone_replica_count" -ne "$CAMUNDA_REGION_SLOTS" ]; then
    echo "ERROR: CAMUNDA_ZONE_REPLICAS ('$CAMUNDA_ZONE_REPLICAS') has $_zone_replica_count entries for $CAMUNDA_REGION_SLOTS slots." >&2
    echo "       It must name every slot, including ones not deployed yet, so that activate-region.sh" >&2
    echo "       knows the replica count of the zone it adds." >&2
    return 1 2>/dev/null || exit 1
fi

_slot=0
_rf=0
for _replicas in $CAMUNDA_ZONE_REPLICAS; do
    if ! [[ "$_replicas" =~ ^[0-9]+$ ]] || [ "$_replicas" -lt 1 ]; then
        echo "ERROR: zone slot $_slot has numberOfReplicas '$_replicas'; every zone needs at least 1." >&2
        return 1 2>/dev/null || exit 1
    fi
    if [ "$_replicas" -gt "$CAMUNDA_BROKERS_PER_REGION" ]; then
        echo "ERROR: zone slot $_slot has $_replicas replicas but only $CAMUNDA_BROKERS_PER_REGION brokers." >&2
        echo "       A zone cannot hold more replicas of a partition than it has brokers." >&2
        return 1 2>/dev/null || exit 1
    fi
    [ "$_slot" -lt "$CAMUNDA_ACTIVE_REGIONS" ] && _rf=$((_rf + _replicas))
    _slot=$((_slot + 1))
done

# Only declared, active zones contribute to the replication factor. The chart
# derives placement from the zone list, and check-cluster-topology.sh checks it.
if [ -z "${CAMUNDA_REPLICATION_FACTOR:-}" ]; then
    CAMUNDA_REPLICATION_FACTOR="$_rf"
fi
export CAMUNDA_REPLICATION_FACTOR
unset _slot _replicas _zone_replica_count _rf

# No clusterSize/slots divisibility check any more: with the zone-aware scheme the chart
# derives the StatefulSet replica count from the zone's own numberOfBrokers, and
# the cluster size from the sum across zones. Asymmetric zones are therefore
# expressible, which the integer division of node-ID numbering could not do.

echo "Multi-region environment:"
echo "  region slots       : $CAMUNDA_REGION_SLOTS (active: $CAMUNDA_ACTIVE_REGIONS)"
echo "  aws regions        : $AWS_REGIONS"
echo "  kube contexts      : $CLUSTER_CONTEXTS"
echo "  submariner ids     : $SUBMARINER_CLUSTER_IDS"
echo "  namespace          : $CAMUNDA_NAMESPACE"
echo "  cluster size       : $CAMUNDA_CLUSTER_SIZE ($CAMUNDA_BROKERS_PER_REGION per region)"
echo "  partitions         : $CAMUNDA_PARTITION_COUNT"
echo "  replication factor : $CAMUNDA_REPLICATION_FACTOR"

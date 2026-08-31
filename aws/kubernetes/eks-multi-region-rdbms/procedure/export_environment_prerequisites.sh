#!/bin/bash
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

# Number of REGION SLOTS, and therefore of zones. Fixed for the lifetime of the
# Camunda cluster: the partition layout reserves replicas per zone, so changing
# it redistributes every partition. A broker's own ID is its index INSIDE its
# zone, so the slot count does not enter into it.
export CAMUNDA_REGION_SLOTS="${CAMUNDA_REGION_SLOTS:-3}"

# Number of slots currently deployed. Must be CAMUNDA_REGION_SLOTS or
# CAMUNDA_REGION_SLOTS - 1; see ../README.md.
export CAMUNDA_ACTIVE_REGIONS="${CAMUNDA_ACTIVE_REGIONS:-3}"

# AWS regions, kubectl contexts and Submariner cluster IDs, one entry per slot.
# The Submariner cluster ID becomes the first DNS label of every cross-cluster
# name (<clusterID>.<service>.<namespace>.svc.clusterset.local) and must be a
# valid DNS-1123 label.
export AWS_REGIONS="${AWS_REGIONS:-eu-west-2 eu-west-3 eu-central-2}"
export CLUSTER_CONTEXTS="${CLUSTER_CONTEXTS:-cluster-london cluster-paris cluster-zurich}"
export SUBMARINER_CLUSTER_IDS="${SUBMARINER_CLUSTER_IDS:-london paris zurich}"

# Slot hosting the Submariner broker. Any cluster can host it; the broker only
# stores metadata and its loss does not interrupt established tunnels.
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
export CAMUNDA_CLUSTER_SIZE="${CAMUNDA_CLUSTER_SIZE:-$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_REGION_SLOTS))}"
export CAMUNDA_PARTITION_COUNT="${CAMUNDA_PARTITION_COUNT:-$CAMUNDA_CLUSTER_SIZE}"

# One replica per zone, so the replication factor equals the zone count. With
# zone awareness the chart derives both from the zone list rather than from this
# value; it is kept because the topology check asserts against it.
export CAMUNDA_REPLICAS_PER_ZONE="${CAMUNDA_REPLICAS_PER_ZONE:-1}"
export CAMUNDA_REPLICATION_FACTOR="${CAMUNDA_REPLICATION_FACTOR:-$((CAMUNDA_REPLICAS_PER_ZONE * CAMUNDA_REGION_SLOTS))}"

# Zone awareness is not in a released chart yet. The reference architecture
# builds the chart from source, so it is pinned to the branch implementing
# `global.multiregion.mode: zoned`.
#
# The alternative was hand-assembling CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_*
# environment variables against the released chart. That does not work: the
# released chart derives the node ID from `regions` and `regionId`, which is the
# arithmetic zone awareness replaces, and no value passed from outside overrides
# it -- `${VAR:-default}` treats an empty value as unset. See
# camunda/camunda-platform-helm#6807.
#
# TODO [release-duty]: drop this pin once zoned mode is in a released chart.
export CAMUNDA_HELM_CHART_GIT_REF="${CAMUNDA_HELM_CHART_GIT_REF:-feat/zoned-mode-node-id}"

# TODO [release-duty]: pin to the released chart version and switch
# HELM_CHART_REF to https://helm.camunda.io once 8.10 is generally available.
# renovate: datasource=helm depName=camunda-platform versioning=regex:^15(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
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

# A majority of the slots has to be live, not "all but one". The two agree at
# three and four slots and part company at two, where `slots - 1` would accept a
# single active region and one replica of two is not a majority. Terraform is
# saved from that by a separate `active_region_count >= 2` validation; this
# script is the safety net when the procedures are run by hand, so it states the
# invariant itself.
if [ "$((2 * CAMUNDA_ACTIVE_REGIONS))" -le "$CAMUNDA_REGION_SLOTS" ]; then
    echo "ERROR: CAMUNDA_ACTIVE_REGIONS ($CAMUNDA_ACTIVE_REGIONS) is not a majority of $CAMUNDA_REGION_SLOTS slots." >&2
    echo "       With one replica per slot, every Zeebe partition would lose its majority" >&2
    echo "       and the cluster could not form a quorum." >&2
    return 1 2>/dev/null || exit 1
fi

# No clusterSize/slots divisibility check any more: in zoned mode the chart
# derives the StatefulSet replica count from the zone's own numberOfBrokers, and
# the cluster size from the sum across zones. Asymmetric zones are therefore
# expressible, which the legacy integer division could not do.

echo "Multi-region environment:"
echo "  region slots       : $CAMUNDA_REGION_SLOTS (active: $CAMUNDA_ACTIVE_REGIONS)"
echo "  aws regions        : $AWS_REGIONS"
echo "  kube contexts      : $CLUSTER_CONTEXTS"
echo "  submariner ids     : $SUBMARINER_CLUSTER_IDS"
echo "  namespace          : $CAMUNDA_NAMESPACE"
echo "  cluster size       : $CAMUNDA_CLUSTER_SIZE ($CAMUNDA_BROKERS_PER_REGION per region)"
echo "  partitions         : $CAMUNDA_PARTITION_COUNT"
echo "  replication factor : $CAMUNDA_REPLICATION_FACTOR"

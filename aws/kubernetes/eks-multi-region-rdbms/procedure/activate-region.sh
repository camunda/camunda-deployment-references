#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Brings a previously empty region slot online without interrupting the running
# Camunda cluster.
#
#   ./activate-region.sh <slot>
#
# Prerequisites:
#   1. Terraform has been applied with `active_region_count` raised to include
#      the slot, so its EKS cluster, Transit Gateway attachments and firewall
#      rules exist.
#   2. A kubectl context for the new cluster exists and is listed in
#      CLUSTER_CONTEXTS.
#   3. CAMUNDA_ACTIVE_REGIONS already reflects the NEW number of active regions.
#
# The slot count, and therefore every broker's identity, was fixed at bootstrap,
# so no existing broker is renumbered and no partition is redistributed.
#
# INCOMPLETE. This was written believing the partition layout already reserved
# replicas for the empty slot, so bringing its brokers up was the whole job.
# It does not: the zone list now covers only DEPLOYED zones, so the regions
# already running have never heard of this one, and its brokers have nothing to
# join. The missing step is announcing the zone to them --
#   POST /actuator/cluster/zones/<zone>  {numberOfReplicas, priority, brokers}
# -- which procedure/failback.sh already does when re-adding a force-removed
# zone. Until that is lifted into a shared helper and called here,
# TestMultiRegionActivateRegion is expected to fail, and step 6/6 below is where
# it will surface.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"

if [ $# -ne 1 ]; then
    echo "usage: $0 <region-slot>" >&2
    exit 1
fi

SLOT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/lib-management-api.sh"

if [ "$SLOT" -ge "$CAMUNDA_REGION_SLOTS" ]; then
    echo "ERROR: slot $SLOT is outside the provisioned slot range (0..$((CAMUNDA_REGION_SLOTS - 1)))." >&2
    echo "       The slot count is immutable; growing it renumbers every broker." >&2
    exit 1
fi

if [ "$SLOT" -ge "$CAMUNDA_ACTIVE_REGIONS" ]; then
    echo "ERROR: CAMUNDA_ACTIVE_REGIONS ($CAMUNDA_ACTIVE_REGIONS) does not yet include slot $SLOT." >&2
    echo "       Export CAMUNDA_ACTIVE_REGIONS=$((SLOT + 1)) (or higher) and re-run." >&2
    exit 1
fi

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
new_context="${contexts[$SLOT]}"
survivor_context="${contexts[0]}"

echo "==> 1/6 Joining region slot $SLOT ($new_context) to the Submariner ClusterSet"
"$SCRIPT_DIR/submariner/join-clusters.sh" "$SLOT"
"$SCRIPT_DIR/submariner/verify-submariner.sh"

echo "==> 2/6 Preparing $new_context: storage class, namespace and RDBMS secret"
# The new cluster has none of these. The storage class in particular is easy to
# forget because the bootstrap configured it for the regions that existed then:
# without it the broker PVCs never bind and the Pods sit in Pending, which the
# rest of this script would then wait out as a failure to join.
"$SCRIPT_DIR/storageclass-configure.sh"
"$SCRIPT_DIR/storageclass-verify.sh"
"$SCRIPT_DIR/setup-namespaces.sh"
"$SCRIPT_DIR/create-rdbms-secret.sh"

echo "==> 3/6 Rendering the Helm values with the new contact point list"
. "$SCRIPT_DIR/generate-zeebe-helm-values.sh"
"$SCRIPT_DIR/assemble-envsubst-values.sh"

echo "==> 4/6 Installing Camunda in region slot $SLOT"
# Only the new region is installed. The contact point list matters at bootstrap;
# once a cluster is formed a newcomer only has to reach one member, and the rest
# learn about it by gossip. So the regions already running keep their shorter
# list and are not restarted. Their values files now carry the longer one, which
# they pick up on their next upgrade.
"$SCRIPT_DIR/install-chart.sh" "$SLOT"

echo "==> 5/6 Exporting the new region's services to the ClusterSet"
"$SCRIPT_DIR/submariner/export-services.sh"

echo "==> 6/6 Waiting for the new brokers to join, then verifying the topology"
# check-cluster-topology.sh already polls the gateway until the expected broker
# count is present and then asserts the shape, so the wait and the verification
# are the same call.
if ! TOPOLOGY_TIMEOUT_SECONDS="${ACTIVATE_REGION_TIMEOUT_SECONDS:-900}" \
    "$SCRIPT_DIR/check-cluster-topology.sh"; then
    echo >&2
    echo "The brokers of region slot $SLOT are ACTIVE members of the configuration" >&2
    echo "below, so this is not a membership problem and no cluster change would fix" >&2
    echo "it: the processes are not reaching the rest of the cluster. Check that the" >&2
    echo "new region's Pods are running rather than Pending, and that its services" >&2
    echo "are exported to the ClusterSet." >&2
    echo >&2
    camunda::management "$survivor_context" GET /actuator/cluster >&2
    exit 1
fi

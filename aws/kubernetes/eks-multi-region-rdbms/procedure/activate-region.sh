#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Brings a previously empty region slot online without stopping the running
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
# The slot count, and therefore every broker's identity, was fixed at bootstrap.
# Activating a slot only fills in the replicas that the partition layout already
# reserved for it; no existing broker is renumbered and no partition is
# redistributed.
#
# It is not free, though. The running regions are restarted so they learn the new
# region's contact point, one Pod at a time, and each partition spends that
# window one replica short. See "What activating a zone costs" in ../README.md.

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

echo "==> 4/6 Installing Camunda in region slot $SLOT and refreshing the running regions"
# Every active slot is (re)installed, not only the new one. The running regions
# hold the contact point list they started with, and nothing hands them a new
# one at runtime: a broker they were never told about is refused outright,
#
#   'zurich_0', but member is not known. Known members are '[Member{id=london_0 ...
#
# so the new region can never register. Step 3 has already rendered every slot's
# values with the longer list; applying them is what lets the newcomer in.
#
# The new region goes FIRST. Every broker starts behind an initContainer that
# waits for the per-Pod clusterset DNS names of all its contact points, so a
# running region restarted before the new one exists blocks there for the full
# gate timeout, twelve minutes per Pod, for nothing.
#
# Those restarts are the cost of activation: one Pod at a time, and while a Pod
# is down its partitions run one replica short. See "What activating a zone
# costs" in ../README.md.
install_order=("$SLOT")
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    if [ "$i" -ne "$SLOT" ]; then
        install_order+=("$i")
    fi
done
"$SCRIPT_DIR/install-chart.sh" "${install_order[@]}"

echo "==> 5/6 Exporting the new region's services to the ClusterSet"
"$SCRIPT_DIR/submariner/export-services.sh"

echo "==> 6/6 Waiting for the new brokers to join the Zeebe cluster"
node_ids="$(camunda::region_node_ids "$SLOT")"
echo "    Expected broker node IDs for slot $SLOT: $node_ids"

expected_total=$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_ACTIVE_REGIONS))
# Long enough to cover the rolling restarts of step 4 and the brokers coming
# back behind them, short enough to leave the topology verification that follows
# its own budget inside the caller's timeout.
deadline=$((SECONDS + ${ACTIVATE_REGION_TIMEOUT_SECONDS:-900}))

while true; do
    joined="$(camunda::registered_broker_count "$survivor_context")"

    if [ "${joined:-0}" -ge "$expected_total" ]; then
        echo "    All $expected_total brokers joined the cluster."
        break
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo
        echo "ERROR: the brokers of region slot $SLOT did not register within the timeout." >&2
        echo "       They are already ACTIVE members of the configuration below, so this" >&2
        echo "       is not a membership problem and no cluster change would fix it: the" >&2
        echo "       processes are not reaching the rest of the cluster. Check that step" >&2
        echo "       4 restarted the running regions, and that the new region's services" >&2
        echo "       are exported to the ClusterSet." >&2
        echo >&2
        camunda::management "$survivor_context" GET /actuator/cluster >&2
        exit 1
    fi

    echo "    $joined/$expected_total brokers joined, waiting ..."
    sleep 20
done

echo
echo "Region slot $SLOT is active. Verifying the resulting topology:"
"$SCRIPT_DIR/check-cluster-topology.sh"

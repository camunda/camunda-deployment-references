#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Brings a previously empty region slot online, without interrupting the running
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
# What makes this non-disruptive is that the slot count, and therefore every
# broker node ID, was fixed at bootstrap. Activating a slot only fills in the
# replicas that the partition layout already reserved for it; no existing broker
# is renumbered and no partition is redistributed.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REGION_SLOTS:?CAMUNDA_REGION_SLOTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_BROKERS_PER_REGION:?CAMUNDA_BROKERS_PER_REGION must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_REPLICATION_FACTOR:?CAMUNDA_REPLICATION_FACTOR must be set, source export_environment_prerequisites.sh}"

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

echo "==> 2/6 Creating the namespace and the RDBMS secret in $new_context"
"$SCRIPT_DIR/setup-namespaces.sh"
"$SCRIPT_DIR/create-rdbms-secret.sh"

echo "==> 3/6 Rendering the Helm values with the new contact point list"
. "$SCRIPT_DIR/generate-zeebe-helm-values.sh"
"$SCRIPT_DIR/assemble-envsubst-values.sh"

echo "==> 4/6 Installing Camunda in region slot $SLOT"
# Only the new region is installed. The already running regions learn about the
# new brokers through cluster membership gossip; their values files now carry a
# longer contact point list, which is picked up harmlessly on their next
# upgrade. Restarting them here would be a needless rolling restart.
"$SCRIPT_DIR/install-chart.sh" "$SLOT"

echo "==> 5/6 Exporting the new region's services to the ClusterSet"
"$SCRIPT_DIR/submariner/export-services.sh"

echo "==> 6/6 Waiting for the new brokers to join the Zeebe cluster"
node_ids="$(camunda::region_node_ids "$SLOT")"
echo "    Expected broker node IDs for slot $SLOT: $node_ids"

expected_total=$((CAMUNDA_BROKERS_PER_REGION * CAMUNDA_ACTIVE_REGIONS))
# Ten minutes is a generous window for gossip to carry the new brokers in. The
# rest of the budget belongs to what happens when it does not: the membership
# change and then the topology verification, which together need most of the
# step's hour.
deadline=$((SECONDS + ${ACTIVATE_REGION_TIMEOUT_SECONDS:-600}))

while true; do
    joined="$(camunda::registered_broker_count "$survivor_context")"

    if [ "${joined:-0}" -ge "$expected_total" ]; then
        echo "    All $expected_total brokers joined the cluster."
        break
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo
        echo "The new brokers did not join on their own within the timeout."
        echo "They are part of the partition layout computed at bootstrap, so this"
        echo "normally happens automatically. Falling back to an explicit membership"
        echo "change through the cluster scaling API."
        echo
        echo "    Cluster membership as the survivors see it:"
        camunda::management "$survivor_context" GET /actuator/cluster
        echo

        add_json="$(printf '%s\n' "$node_ids" | tr ' ' '\n' | jq -R 'tonumber' | jq -sc .)"
        body="$(jq -nc \
            --argjson add "$add_json" \
            --argjson rf "$CAMUNDA_REPLICATION_FACTOR" \
            '{brokers: {add: $add}, partitions: {replicationFactor: $rf}}')"

        echo "    PATCH /actuator/cluster $body"
        camunda::management "$survivor_context" PATCH /actuator/cluster "$body"
        camunda::wait_for_cluster_change "$survivor_context"
        break
    fi

    echo "    $joined/$expected_total brokers joined, waiting ..."
    sleep 20
done

echo
echo "Region slot $SLOT is active. Verifying the resulting topology:"
"$SCRIPT_DIR/check-cluster-topology.sh"

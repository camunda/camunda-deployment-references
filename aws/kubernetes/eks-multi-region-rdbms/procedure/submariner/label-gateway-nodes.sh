#!/bin/bash
set -euo pipefail

# Labels one node per cluster as a Submariner gateway.
#
#   ./label-gateway-nodes.sh [slot]
#
# Submariner runs the IPsec tunnel endpoint on the host network of a labelled
# node. Labelling explicitly (instead of letting `subctl join --label-gateway`
# pick one) keeps the choice deterministic across re-runs, which matters because
# the gateway node IP is what the remote clusters dial.
#
# The optional slot argument restricts the labelling to one region, which is
# what ../activate-region.sh needs: re-labelling a running region could move the
# gateway to another node and migrate the established tunnels for nothing.
#
# Run it AFTER ../configure-vpc-cni-custom-networking.sh: that procedure
# replaces the nodes, and the label with them.
#
# A single gateway per cluster is a single point of failure for cross-region
# traffic: Submariner elects a new active gateway if more nodes carry the label.
# Set SUBMARINER_GATEWAY_NODES_PER_CLUSTER to label more than one for HA.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

GATEWAYS_PER_CLUSTER="${SUBMARINER_GATEWAY_NODES_PER_CLUSTER:-1}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

if [ $# -ge 1 ]; then
    slots=("$1")
else
    slots=()
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        slots+=("$i")
    done
fi

for i in "${slots[@]}"; do
    context="${contexts[$i]}"

    mapfile -t nodes < <(kubectl --context "$context" get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)

    if [ "${#nodes[@]}" -lt "$GATEWAYS_PER_CLUSTER" ]; then
        echo "ERROR: $context has ${#nodes[@]} node(s), need at least $GATEWAYS_PER_CLUSTER for the gateway label." >&2
        exit 1
    fi

    # Sorted node list keeps the selection stable across re-runs.
    for ((g = 0; g < GATEWAYS_PER_CLUSTER; g++)); do
        node="${nodes[$g]}"
        echo "Labelling $context/$node as a Submariner gateway"
        kubectl --context "$context" label node "$node" submariner.io/gateway=true --overwrite
    done
done

echo
echo "Gateway nodes:"
for i in "${slots[@]}"; do
    kubectl --context "${contexts[$i]}" get nodes -l submariner.io/gateway=true
done

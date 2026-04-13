#!/bin/bash
set -euo pipefail

# Cluster 0
CLUSTER_0_BROKER_NODE_NAME="$(oc --context "$CLUSTER_0" get nodes -o jsonpath='{.items[0].metadata.name}')"

echo "Using node '$CLUSTER_0_BROKER_NODE_NAME' as the broker for Submariner in cluster '$CLUSTER_0'."
oc --context "$CLUSTER_0" label node "$CLUSTER_0_BROKER_NODE_NAME" submariner.io/gateway=true

# Cluster 1
CLUSTER_1_BROKER_NODE_NAME="$(oc --context "$CLUSTER_1" get nodes -o jsonpath='{.items[0].metadata.name}')"

echo "Using node '$CLUSTER_1_BROKER_NODE_NAME' as the broker for Submariner in cluster '$CLUSTER_1'."
oc --context "$CLUSTER_1" label node "$CLUSTER_1_BROKER_NODE_NAME" submariner.io/gateway=true

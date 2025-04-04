#!/bin/bash

# Cluster 1
CLUSTER_1_BROKER_NODE_NAME="$(oc --context "$CLUSTER_1_NAME" get nodes -o jsonpath='{.items[0].metadata.name}')"

echo "Using node '$CLUSTER_1_BROKER_NODE_NAME' as the broker for Submariner in cluster '$CLUSTER_1_NAME'."
oc --context "$CLUSTER_1_NAME" label node "$CLUSTER_1_BROKER_NODE_NAME" submariner.io/gateway=true

# Cluster 2
CLUSTER_2_BROKER_NODE_NAME="$(oc --context "$CLUSTER_2_NAME" get nodes -o jsonpath='{.items[0].metadata.name}')"

echo "Using node '$CLUSTER_2_BROKER_NODE_NAME' as the broker for Submariner in cluster '$CLUSTER_2_NAME'."
oc --context "$CLUSTER_2_NAME" label node "$CLUSTER_2_BROKER_NODE_NAME" submariner.io/gateway=true

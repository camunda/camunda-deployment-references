#!/bin/bash

# Cluster 0
oc --context "$CLUSTER_0_NAME" get nodes

# Cluster 1
oc --context "$CLUSTER_1_NAME" get nodes

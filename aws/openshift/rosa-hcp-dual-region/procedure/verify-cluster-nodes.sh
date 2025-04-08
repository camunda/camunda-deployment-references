#!/bin/bash

# Cluster 1
oc --context "$CLUSTER_1_NAME" get nodes

# Cluster 2
oc --context "$CLUSTER_2_NAME" get nodes

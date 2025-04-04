#!/bin/bash

oc --context "$CLUSTER_1_NAME" get nodes -l submariner.io/gateway=true
oc --context "$CLUSTER_2_NAME" get nodes -l submariner.io/gateway=true

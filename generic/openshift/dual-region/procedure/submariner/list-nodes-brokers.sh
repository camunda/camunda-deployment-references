#!/bin/bash

oc --context "$CLUSTER_0" get nodes -l submariner.io/gateway=true
oc --context "$CLUSTER_1" get nodes -l submariner.io/gateway=true

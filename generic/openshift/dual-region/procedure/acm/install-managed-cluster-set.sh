#!/bin/bash

oc --context "$CLUSTER_1_NAME" get mch -A
oc --context "$CLUSTER_1_NAME" apply -f managed-cluster-set.yml

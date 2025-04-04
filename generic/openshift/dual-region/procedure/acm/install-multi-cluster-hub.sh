#!/bin/bash

oc --context "$CLUSTER_1_NAME" apply -f multi-cluster-hub.yml

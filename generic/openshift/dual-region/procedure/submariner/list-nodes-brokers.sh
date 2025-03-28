#!/bin/bash

# TODO: integrate in https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/openshift/redhat-openshift-dual-region/#submariner

oc --context "$CLUSTER_1_NAME" get nodes -l submariner.io/gateway=true
oc --context "$CLUSTER_2_NAME" get nodes -l submariner.io/gateway=true

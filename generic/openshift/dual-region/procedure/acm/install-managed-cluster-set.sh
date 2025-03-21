#!/bin/bash

# TODO: integrate in https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/openshift/redhat-openshift-dual-region/#advanced-cluster-management

oc --context "$CLUSTER_1_NAME" get mch -A
oc --context "$CLUSTER_1_NAME" apply -f managed-cluster-set.yml

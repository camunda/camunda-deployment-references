#!/bin/bash

# TODO: integrate in https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/openshift/redhat-openshift-dual-region/#submariner

envsubst < submariner.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

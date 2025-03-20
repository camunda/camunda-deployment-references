#!/bin/bash

# TODO: integrate in https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/openshift/redhat-openshift-dual-region/#advanced-cluster-management

while true; do
    STATUS=$(oc --context "$CLUSTER_1_NAME" get mch -n open-cluster-management multiclusterhub)
    echo "$STATUS"

    if echo "$STATUS" | grep -q "Running"; then
        echo "Multiclusterhub is Running!"
        exit 0
    fi

    sleep 5
done

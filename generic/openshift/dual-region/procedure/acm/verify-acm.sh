#!/bin/bash

# TODO: integrate in https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/openshift/redhat-openshift-dual-region/#advanced-cluster-management

while true; do
    STATUS=$(oc --context "$CLUSTER_1_NAME" --namespace open-cluster-management get csv)
    echo "$STATUS"

    if echo "$STATUS" | grep -q "Succeeded"; then
        echo "CSV is Succeeded!"
        exit 0
    fi

    sleep 5
done

# Example output:
# NAME                                  DISPLAY                                      VERSION   REPLACES                              PHASE
# advanced-cluster-management.v2.12.2   Advanced Cluster Management for Kubernetes   2.12.2    advanced-cluster-management.v2.12.1   Succeeded

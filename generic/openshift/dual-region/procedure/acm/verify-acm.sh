#!/bin/bash

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
# advanced-cluster-management.v2.13.2   Advanced Cluster Management for Kubernetes   2.13.2    advanced-cluster-management.v2.13.2   Succeeded

#!/bin/bash

# TODO: integrate in https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/openshift/redhat-openshift-dual-region/#submariner

CLUSTERS=("$CLUSTER_1_NAME" "$CLUSTER_2_NAME")

# Check the status of both clusters
while true; do
    last_cluster_ok=false

    for CLUSTER_NAME in "${CLUSTERS[@]}"; do
        STATUS=$(subctl show all --contexts "$CLUSTER_NAME")
        echo "Status of Cluster ($CLUSTER_NAME):"
        echo "$STATUS"

        if echo "$STATUS" | grep -q "All connections (1) are established" && \
           echo "$STATUS" | grep -q " connected "; then
            echo "Gateway and Connection for $CLUSTER_NAME are correctly established!"
            last_cluster_ok=true
        else
            echo "$CLUSTER_NAME is not fully connected, retrying..."
        fi
    done

    if [ "$last_cluster_ok" = true ]; then
        echo "Both clusters are correctly connected!"
        exit 0
    fi

    sleep 5
done

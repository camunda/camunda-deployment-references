#!/bin/bash

CLUSTERS=("$CLUSTER_1_NAME" "$CLUSTER_2_NAME")

# Check the status of both clusters
while true; do
    all_connected=true

    for CLUSTER_NAME in "${CLUSTERS[@]}"; do
        STATUS=$(subctl show all --contexts "$CLUSTER_NAME")
        echo "Status of Cluster ($CLUSTER_NAME):"
        echo "$STATUS"

        if echo "$STATUS" | grep -q "All connections (1) are established" && \
           echo "$STATUS" | grep -q " connected "; then
            echo "Gateway and Connection for $CLUSTER_NAME are correctly established!"
        else
            echo "$CLUSTER_NAME is not fully connected, retrying..."
            all_connected=false
        fi
    done

    if [ "$all_connected" = true ]; then
        echo "Both clusters are correctly connected!"
        exit 0
    fi

    sleep 5
done

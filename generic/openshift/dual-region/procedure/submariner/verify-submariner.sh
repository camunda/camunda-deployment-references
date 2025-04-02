#!/bin/bash

while true; do
    STATUS=$(oc --context "$CLUSTER_1_NAME" get managedclusteraddon -A | grep 'submariner')
    # display the status
    oc --context "$CLUSTER_1_NAME" -n "oc-clusters-broker" describe Broker
    oc --context "$CLUSTER_1_NAME" get managedclusteraddon -A | grep -E 'NAME|submariner'

    if echo "$STATUS" | awk '{if ($3=="True" && $4=="False" && $5=="") next; else exit 1}'; then
        echo "All submariner addons are Available=True, Degraded=False, and not Progressing!"
        exit 0
    fi

    sleep 5
done

# Example output:
# NAMESPACE          NAME                          AVAILABLE   DEGRADED   PROGRESSING
# cluster-region-2   submariner                    True                   False
# local-cluster      submariner                    True                   False

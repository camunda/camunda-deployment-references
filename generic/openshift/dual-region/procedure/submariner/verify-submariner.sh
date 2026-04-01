#!/bin/bash
set -euo pipefail

while true; do
    oc_output=$(oc --context "$CLUSTER_0" get managedclusteraddon -A)
    STATUS=$(echo "$oc_output" | grep 'submariner' || true)
    # display the status
    oc --context "$CLUSTER_0" -n "oc-clusters-broker" describe Broker
    echo "$oc_output" | grep -E 'NAME|submariner' || true

    if [ -z "$STATUS" ]; then
        echo "No submariner addons found yet, waiting..."
        sleep 5
        continue
    fi

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

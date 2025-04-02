#!/bin/bash

while true; do
    STATUS=$(oc --context "$CLUSTER_1_NAME" get managedclusters)
    echo "$STATUS"

    if echo "$STATUS" | awk 'NR>1 {if ($2=="true" && $4=="True" && $5=="True") next; else exit 1}'; then
        echo "All managed clusters are Accepted=True, Joined=True, and Available=True!"
        exit 0
    fi

    sleep 5
done

# Example output:
# NAME            HUB ACCEPTED   MANAGED CLUSTER URLS                                 JOINED   AVAILABLE   AGE
# cl-oc-2         true           https://api.cl-oc-2.5egh.p3.openshiftapps.com:443    True     True        50s
# local-cluster   true           https://api.cl-oc-1.f70c.p3.openshiftapps.com:443   True     True        36m

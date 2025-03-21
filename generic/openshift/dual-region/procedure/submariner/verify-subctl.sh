#!/bin/bash

# TODO: integrate in https://docs.camunda.io/docs/8.7/self-managed/setup/deploy/openshift/redhat-openshift-dual-region/#submariner

while true; do
    STATUS=$(subctl show all --contexts "$CLUSTER_1_NAME,$CLUSTER_2_NAME")
    echo "$STATUS"

    # Vérifie que le statut du Gateway et de la Connection est correct
    if echo "$STATUS" | grep -q "Gateway's status: All connections (1) are established" && \
       echo "$STATUS" | grep -q "Connection's status: connected"; then
        echo "Gateway and Connection are correctly established!"
        exit 0
    fi

    sleep 5
done

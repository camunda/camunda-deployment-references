#!/bin/bash

while true; do
    kubectl get pods -n "$CAMUNDA_NAMESPACE" --output=wide

    if [ "$(kubectl get pods -n "$CAMUNDA_NAMESPACE" --field-selector=status.phase!=Running -o name | wc -l)" -eq 0 ] &&
        [ "$(kubectl get pods -n "$CAMUNDA_NAMESPACE" -o json | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false)' | wc -l)" -eq 0 ]; then
        echo "All pods are Running and Healthy - Installation completed!"
        exit 0
    else
        echo "Some pods are not Running or Healthy, please wait..."
        sleep 5
    fi
done

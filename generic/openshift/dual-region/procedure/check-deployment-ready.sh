#!/bin/bash

set -euo pipefail

while true; do
  echo "Checking pods in context: $CLUSTER_1_NAME, namespace: $CAMUNDA_NAMESPACE_1";
  kubectl --context="$CLUSTER_1_NAME" get pods -n "$CAMUNDA_NAMESPACE_1" --output=wide;
  if [ "$(kubectl --context="$CLUSTER_1_NAME" get pods -n "$CAMUNDA_NAMESPACE_1" --field-selector=status.phase!=Running -o name | wc -l)" -eq 0 ] &&
     [ "$(kubectl --context="$CLUSTER_1_NAME" get pods -n "$CAMUNDA_NAMESPACE_1" -o json | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false)' | wc -l)" -eq 0 ];
  then
    echo "All pods are Running and Healthy in context: $CLUSTER_1_NAME, namespace: $CAMUNDA_NAMESPACE_1 - Installation completed!";
  else
    echo "Some pods are not Running or Healthy in context: $CLUSTER_1_NAME, namespace: $CAMUNDA_NAMESPACE_1";
    sleep 5;
    continue;
  fi

  echo "Checking pods in context: $CLUSTER_2_NAME, namespace: $CAMUNDA_NAMESPACE_2";
  kubectl --context="$CLUSTER_2_NAME" get pods -n "$CAMUNDA_NAMESPACE_2" --output=wide;
  if [ "$(kubectl --context="$CLUSTER_2_NAME" get pods -n "$CAMUNDA_NAMESPACE_2" --field-selector=status.phase!=Running -o name | wc -l)" -eq 0 ] &&
     [ "$(kubectl --context="$CLUSTER_2_NAME" get pods -n "$CAMUNDA_NAMESPACE_2" -o json | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false)' | wc -l)" -eq 0 ];
  then
    echo "OK: All pods are Running and Healthy in context: $CLUSTER_2_NAME, namespace: $CAMUNDA_NAMESPACE_2 - Installation completed!";
    echo "OK: All pods are healthy across both contexts.";
    echo "Installation completed.";
    exit 0;
  else
    echo "Some pods are not Running or Healthy in context: $CLUSTER_2_NAME, namespace: $CAMUNDA_NAMESPACE_2";
  fi

  sleep 5;
done

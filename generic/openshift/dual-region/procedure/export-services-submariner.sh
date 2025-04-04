#!/bin/bash

echo "Exporting services from $CLUSTER_1_NAME in $CAMUNDA_NAMESPACE_1 using subctl"

for svc in $(oc --context "$CLUSTER_1_NAME" get svc -n "$CAMUNDA_NAMESPACE_1" -o jsonpath='{.items[*].metadata.name}'); do
    subctl --context "$CLUSTER_1_NAME" export service --namespace "$CAMUNDA_NAMESPACE_1" "$svc"
done

echo "Exporting services from $CLUSTER_2_NAME in $CAMUNDA_NAMESPACE_2 using subctl"

for svc in $(oc --context "$CLUSTER_2_NAME" get svc -n "$CAMUNDA_NAMESPACE_2" -o jsonpath='{.items[*].metadata.name}'); do
    subctl --context "$CLUSTER_2_NAME" export service --namespace "$CAMUNDA_NAMESPACE_2" "$svc"
done

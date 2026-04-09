#!/bin/bash
set -euo pipefail
# Creates namespaces in both clusters.
#
# Duplicating namespaces in each cluster is required for Submariner to work as expected.
# Each cluster must have both namespaces created.
#
# Required environment variables:
#   CLUSTER_0           - oc context for region 0
#   CLUSTER_1           - oc context for region 1
#   CAMUNDA_NAMESPACE_0 - namespace for region 0
#   CAMUNDA_NAMESPACE_1 - namespace for region 1

create_namespace() {
    local context=$1
    local namespace=$2
    oc --context "$context" create namespace "$namespace" --dry-run=client -o yaml | oc --context "$context" apply -f -
}

# duplicating namespaces in each cluster is required to have submariner working as expected
create_namespace "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0"
create_namespace "$CLUSTER_0" "$CAMUNDA_NAMESPACE_1"
create_namespace "$CLUSTER_1" "$CAMUNDA_NAMESPACE_0"
create_namespace "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1"

# wait some time for the namespaces to be created
sleep 10

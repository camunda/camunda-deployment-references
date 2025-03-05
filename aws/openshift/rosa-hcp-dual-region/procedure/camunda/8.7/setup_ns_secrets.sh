#!/bin/bash

set -e

create_namespace() {
    local context=$1
    local namespace=$2
    oc --context "$context" create namespace "$namespace" --dry-run=client -o yaml | oc --context "$context" apply -f -
}

create_secret() {
    local context=$1
    local namespace=$2
    local secret_name=$3
    local access_key=$4
    local secret_access_key=$5
    oc --context "$context" -n "$namespace" delete secret "$secret_name" --ignore-not-found
    oc --context "$context" -n "$namespace" create secret generic "$secret_name" \
        --from-literal=S3_ACCESS_KEY="$access_key" \
        --from-literal=S3_SECRET_KEY="$secret_access_key"
}

if [ -z "$AWS_ACCESS_KEY_ES" ]; then
    echo "ERROR: AWS_ACCESS_KEY_ES environment variable is not set."
    exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY_ES" ]; then
    echo "ERROR: AWS_SECRET_ACCESS_KEY_ES environment variable is not set."
    exit 1
fi

# duplicating namespaces in each cluster is required to have submariner working as expected
create_namespace "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1"
create_namespace "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_2"
create_namespace "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_1"
create_namespace "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2"

# wait some time for the namespaces to be created
sleep 10

create_secret "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1" "elasticsearch-env-secret" "$AWS_ACCESS_KEY_ES" "$AWS_SECRET_ACCESS_KEY_ES"
create_secret "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2" "elasticsearch-env-secret" "$AWS_ACCESS_KEY_ES" "$AWS_SECRET_ACCESS_KEY_ES"

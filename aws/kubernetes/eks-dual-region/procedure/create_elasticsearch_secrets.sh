#!/bin/bash
# Creates the ECK secure settings secret for Elasticsearch S3 snapshot/backup.
#
# ECK injects these keys into the Elasticsearch keystore at startup.
# The secret name must match the secureSettings reference in the Elasticsearch CRD.
#
# Required environment variables:
#   AWS_ACCESS_KEY_ES        - AWS access key for the S3 backup bucket
#   AWS_SECRET_ACCESS_KEY_ES - AWS secret access key for the S3 backup bucket
#   CLUSTER_0                - kubectl context for region 0
#   CLUSTER_1                - kubectl context for region 1
#   CAMUNDA_NAMESPACE_0      - namespace for region 0
#   CAMUNDA_NAMESPACE_1      - namespace for region 1

set -euo pipefail

SECRET_NAME="elasticsearch-env-secret"

create_namespace() {
    local context=$1
    local namespace=$2
    kubectl --context "$context" create namespace "$namespace" --dry-run=client -o yaml | kubectl --context "$context" apply -f -
}

create_secret() {
    local context=$1
    local namespace=$2

    kubectl --context "$context" -n "$namespace" delete secret "$SECRET_NAME" --ignore-not-found
    kubectl --context "$context" -n "$namespace" create secret generic "$SECRET_NAME" \
        --from-literal=s3.client.camunda.access_key="$AWS_ACCESS_KEY_ES" \
        --from-literal=s3.client.camunda.secret_key="$AWS_SECRET_ACCESS_KEY_ES"
}

if [ -z "${AWS_ACCESS_KEY_ES:-}" ]; then
    echo "Error: AWS_ACCESS_KEY_ES environment variable is not set."
    exit 1
fi

if [ -z "${AWS_SECRET_ACCESS_KEY_ES:-}" ]; then
    echo "Error: AWS_SECRET_ACCESS_KEY_ES environment variable is not set."
    exit 1
fi

create_namespace "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0"
create_namespace "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1"

echo "Creating ECK secure settings secret '$SECRET_NAME' in both regions..."
create_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0"
create_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1"
echo "Done."

#!/bin/bash
# Creates namespaces and ECK secure settings secrets for Elasticsearch S3 snapshot/backup.
#
# ECK injects these keys into the Elasticsearch keystore at startup.
# The secret name must match the secureSettings reference in the Elasticsearch CRD.
#
# Required environment variables:
#   AWS_ACCESS_KEY_ES        - AWS access key for the S3 backup bucket
#   AWS_SECRET_ACCESS_KEY_ES - AWS secret access key for the S3 backup bucket
#   CLUSTER_1_NAME           - oc context for region 1
#   CLUSTER_2_NAME           - oc context for region 2
#   CAMUNDA_NAMESPACE_1      - namespace for region 1
#   CAMUNDA_NAMESPACE_2      - namespace for region 2

set -euo pipefail

create_namespace() {
    local context=$1
    local namespace=$2
    oc --context "$context" create namespace "$namespace" --dry-run=client -o yaml | oc --context "$context" apply -f -
}

create_secret() {
    local context=$1
    local namespace=$2
    local secret_name=$3

    oc --context "$context" -n "$namespace" create secret generic "$secret_name" \
        --from-literal=s3.client.camunda.access_key="$AWS_ACCESS_KEY_ES" \
        --from-literal=s3.client.camunda.secret_key="$AWS_SECRET_ACCESS_KEY_ES" \
        --dry-run=client -o yaml | oc --context "$context" apply -f -
}

if [ -z "${AWS_ACCESS_KEY_ES:-}" ]; then
    echo "ERROR: AWS_ACCESS_KEY_ES environment variable is not set."
    exit 1
fi

if [ -z "${AWS_SECRET_ACCESS_KEY_ES:-}" ]; then
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

SECRET_NAME="elasticsearch-env-secret"

echo "Creating ECK secure settings secret '$SECRET_NAME' in both regions..."
create_secret "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1" "$SECRET_NAME"
create_secret "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2" "$SECRET_NAME"
echo "Done."

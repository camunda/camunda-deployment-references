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

create_namespace() {
    local context=$1
    local namespace=$2
    kubectl --context "$context" create namespace "$namespace" --dry-run=client -o yaml | kubectl --context "$context" apply -f -
}

create_secret() {
    local context=$1
    local namespace=$2
    local secret_name=$3

    kubectl --context "$context" -n "$namespace" delete secret "$secret_name" --ignore-not-found
    kubectl --context "$context" -n "$namespace" create secret generic "$secret_name" \
        --from-literal=s3.client.camunda.access_key="$AWS_ACCESS_KEY_ES" \
        --from-literal=s3.client.camunda.secret_key="$AWS_SECRET_ACCESS_KEY_ES"
}

create_elastic_user_secret() {
    local context=$1
    local namespace=$2
    local secret_name=$3
    local secret_value=$4

    kubectl --context "$context" -n "$namespace" delete secret "$secret_name" --ignore-not-found
    kubectl --context "$context" -n "$namespace" create secret generic "$secret_name" \
        --from-literal=elastic="$secret_value"
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

SECRET_NAME="elasticsearch-env-secret"

echo "Creating ECK secure settings secret '$SECRET_NAME' in both regions..."
create_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "$SECRET_NAME"
create_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "$SECRET_NAME"

elastic_user_secretname="elasticsearch-es-elastic-user"
elastic_user_pass=$(openssl rand -base64 32)
echo "Creating Elasticsearch user secret '$elastic_user_secretname' in both regions..."
create_elastic_user_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "$elastic_user_secretname" "$elastic_user_pass"
create_elastic_user_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "$elastic_user_secretname" "$elastic_user_pass"
echo "Done."

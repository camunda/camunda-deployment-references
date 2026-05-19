#!/bin/bash
# Creates the Elasticsearch env secret for the bundled Bitnami ES subchart.
#
# The secret keys are injected as environment variables into the ES container
# via elasticsearch.extraEnvVarsSecret. The init-keystore.sh initScript reads
# $S3_ACCESS_KEY and $S3_SECRET_KEY to populate the ES keystore for S3 backups.
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

    kubectl --context "$context" -n "$namespace" create secret generic "$secret_name" \
        --from-literal=S3_ACCESS_KEY="$AWS_ACCESS_KEY_ES" \
        --from-literal=S3_SECRET_KEY="$AWS_SECRET_ACCESS_KEY_ES" \
        --dry-run=client -o yaml | kubectl --context "$context" apply -f -
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

echo "Creating Elasticsearch env secret '$SECRET_NAME' in both regions..."
create_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "$SECRET_NAME"
create_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "$SECRET_NAME"
echo "Done."

#!/bin/bash
set -euo pipefail
# Syncs Elasticsearch passwords across regions for cross-region Zeebe exporters.
#
# Each ECK-managed Elasticsearch cluster auto-generates its own 'elasticsearch-es-elastic-user'
# secret with a unique password. For Zeebe exporters to authenticate against the remote region's
# Elasticsearch, each region needs access to the other region's password.
#
# This script reads the ECK-generated passwords and creates region-specific secrets
# in both regions:
#   - elasticsearch-es-password-region-0: password from region 0's Elasticsearch
#   - elasticsearch-es-password-region-1: password from region 1's Elasticsearch
#
# These secrets are referenced by the Zeebe exporter configuration in values-base.yml.
#
# Prerequisites:
#   - ECK Elasticsearch must be deployed and Ready in both regions
#   - The 'elasticsearch-es-elastic-user' secret must exist in both namespaces
#
# Required environment variables:
#   CLUSTER_0           - oc context for region 0
#   CLUSTER_1           - oc context for region 1
#   CAMUNDA_NAMESPACE_0 - namespace for region 0
#   CAMUNDA_NAMESPACE_1 - namespace for region 1

echo "Reading Elasticsearch passwords from both regions..."

PASS_0=$(oc --context "$CLUSTER_0" -n "$CAMUNDA_NAMESPACE_0" get secret elasticsearch-es-elastic-user \
    -o jsonpath='{.data.elastic}' | base64 -d)

PASS_1=$(oc --context "$CLUSTER_1" -n "$CAMUNDA_NAMESPACE_1" get secret elasticsearch-es-elastic-user \
    -o jsonpath='{.data.elastic}' | base64 -d)

if [ -z "$PASS_0" ]; then
    echo "Error: Could not read elasticsearch-es-elastic-user from region 0 ($CLUSTER_0 / $CAMUNDA_NAMESPACE_0)"
    exit 1
fi

if [ -z "$PASS_1" ]; then
    echo "Error: Could not read elasticsearch-es-elastic-user from region 1 ($CLUSTER_1 / $CAMUNDA_NAMESPACE_1)"
    exit 1
fi

create_password_secret() {
    local context=$1
    local namespace=$2
    local secret_name=$3
    local password=$4

    oc --context "$context" -n "$namespace" create secret generic "$secret_name" \
        --from-literal=elastic="$password" \
        --dry-run=client -o yaml | oc --context "$context" apply -f -
}

echo "Creating region-specific password secrets in both regions..."

# Region 0 password → both regions
create_password_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "elasticsearch-es-password-region-0" "$PASS_0"
create_password_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "elasticsearch-es-password-region-0" "$PASS_0"

# Region 1 password → both regions
create_password_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "elasticsearch-es-password-region-1" "$PASS_1"
create_password_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "elasticsearch-es-password-region-1" "$PASS_1"

echo "Done. Cross-region password secrets synchronized:"
echo "  - elasticsearch-es-password-region-0 (from $CAMUNDA_NAMESPACE_0)"
echo "  - elasticsearch-es-password-region-1 (from $CAMUNDA_NAMESPACE_1)"

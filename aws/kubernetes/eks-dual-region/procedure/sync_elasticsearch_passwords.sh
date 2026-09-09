#!/bin/bash
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
# These secrets are referenced by the Zeebe exporter configuration in camunda-values.yml.
# The brokers read them as environment variables, which are only re-read on start, so the
# script then restarts the Zeebe StatefulSet in each region that already runs one.
#
# Prerequisites:
#   - ECK Elasticsearch must be deployed and Ready in both regions
#   - The 'elasticsearch-es-elastic-user' secret must exist in both namespaces
#
# Required environment variables:
#   CLUSTER_0           - kubectl context for region 0
#   CLUSTER_1           - kubectl context for region 1
#   CAMUNDA_NAMESPACE_0 - namespace for region 0
#   CAMUNDA_NAMESPACE_1 - namespace for region 1
#
# Optional environment variables:
#   CAMUNDA_RELEASE_NAME     - Helm release name, used to locate the Zeebe StatefulSet (default: camunda)
#   BROKER_ROLLOUT_TIMEOUT   - how long to wait for each broker restart (default: 5m)

set -euo pipefail

echo "Reading Elasticsearch passwords from both regions..."

PASS_0=$(kubectl --context "$CLUSTER_0" -n "$CAMUNDA_NAMESPACE_0" get secret elasticsearch-es-elastic-user \
    -o jsonpath='{.data.elastic}' | base64 -d)

PASS_1=$(kubectl --context "$CLUSTER_1" -n "$CAMUNDA_NAMESPACE_1" get secret elasticsearch-es-elastic-user \
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

    kubectl --context "$context" -n "$namespace" create secret generic "$secret_name" \
        --from-literal=elastic="$password" \
        --dry-run=client -o yaml | kubectl --context "$context" apply -f -
}

echo "Creating region-specific password secrets in both regions..."

# Region 0 password → both regions
create_password_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "elasticsearch-es-password-region-0" "$PASS_0"
create_password_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "elasticsearch-es-password-region-0" "$PASS_0"

# Region 1 password → both regions
create_password_secret "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "elasticsearch-es-password-region-1" "$PASS_1"
create_password_secret "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "elasticsearch-es-password-region-1" "$PASS_1"

# The brokers read these secrets through secretKeyRef environment variables, and
# Kubernetes never restarts a Pod when the content of a referenced secret changes.
# A broker left running therefore keeps the previous password, and its cross-region
# exporter can never open again ("unable to authenticate user [elastic]"). Roll the
# brokers, and wait, so the new passwords are in place everywhere before anything
# downstream relies on them: a partially rolled StatefulSet silently leaves the
# lowest ordinals holding the old credential.
broker_statefulset="${CAMUNDA_RELEASE_NAME:-camunda}-zeebe"
broker_rollout_timeout="${BROKER_ROLLOUT_TIMEOUT:-5m}"

restart_brokers() {
    local context=$1
    local namespace=$2

    local output
    if ! output=$(kubectl --context "$context" -n "$namespace" rollout restart "statefulset/$broker_statefulset" 2>&1); then
        case "$output" in
            # Camunda is not deployed yet on the initial install, where this script
            # runs right after Elasticsearch. Nothing holds a stale password then.
            *NotFound*)
                echo "  - no $broker_statefulset StatefulSet in $namespace yet, nothing to restart"
                return
                ;;
            *)
                printf '%s\n' "$output" >&2
                exit 1
                ;;
        esac
    fi

    printf '  - %s\n' "$output"
    kubectl --context "$context" -n "$namespace" rollout status "statefulset/$broker_statefulset" \
        --timeout="$broker_rollout_timeout"
}

echo "Restarting the Zeebe brokers so they pick up the new passwords..."

restart_brokers "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0"
restart_brokers "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1"

echo "Done. Cross-region password secrets synchronized:"
echo "  - elasticsearch-es-password-region-0 (from $CAMUNDA_NAMESPACE_0)"
echo "  - elasticsearch-es-password-region-1 (from $CAMUNDA_NAMESPACE_1)"

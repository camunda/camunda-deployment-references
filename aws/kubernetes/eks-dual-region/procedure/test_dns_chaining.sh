#!/bin/bash

set -e

# Get the directory where this script is located (POSIX-compatible)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

create_namespace() {
    local context=$1
    local namespace=$2
    kubectl --context "$context" create namespace "$namespace" --dry-run=client -o yaml | kubectl --context "$context" apply -f -
}

ping_instance() {
    local context=$1
    local source_namespace=$2
    local target_namespace=$3
    i=1
    while [ "$i" -le 5 ]
    do
        echo "Iteration $i - $source_namespace -> $target_namespace"
        if output=$(kubectl --context "$context" exec -n "$source_namespace" sample-nginx -- curl -s --max-time 15 "http://sample-nginx.sample-nginx-peer.$target_namespace.svc.cluster.local" 2>&1); then
            if echo "$output" | grep -q "Welcome to nginx!"; then
                echo "Success: $output"
                return 0
            fi
        fi
        echo "Try again in 15 seconds..."
        sleep 15
        i=$((i + 1))
    done
    echo "Failed to reach the target instance - CoreDNS might not be reloaded yet or wrongly configured"
    return 1
}

create_namespace "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0"
create_namespace "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1"

kubectl --context "$CLUSTER_0" apply -f "$SCRIPT_DIR/manifests/nginx.yml" -n "$CAMUNDA_NAMESPACE_0"
kubectl --context "$CLUSTER_1" apply -f "$SCRIPT_DIR/manifests/nginx.yml" -n "$CAMUNDA_NAMESPACE_1"


kubectl --context "$CLUSTER_0" wait --for=condition=Ready pod/sample-nginx -n "$CAMUNDA_NAMESPACE_0" --timeout=300s
kubectl --context "$CLUSTER_1" wait --for=condition=Ready pod/sample-nginx -n "$CAMUNDA_NAMESPACE_1" --timeout=300s

ping_instance "$CLUSTER_0" "$CAMUNDA_NAMESPACE_0" "$CAMUNDA_NAMESPACE_1"
ping_instance "$CLUSTER_1" "$CAMUNDA_NAMESPACE_1" "$CAMUNDA_NAMESPACE_0"

kubectl --context "$CLUSTER_0" delete -f "$SCRIPT_DIR/manifests/nginx.yml" -n "$CAMUNDA_NAMESPACE_0"
kubectl --context "$CLUSTER_1" delete -f "$SCRIPT_DIR/manifests/nginx.yml" -n "$CAMUNDA_NAMESPACE_1"

#!/bin/bash

set -euo pipefail

# Timeout for DNS propagation wait (in seconds)
DNS_WAIT_TIMEOUT=${DNS_WAIT_TIMEOUT:-300}

echo "Exporting services from $CLUSTER_1_NAME in $CAMUNDA_NAMESPACE_1 using subctl"

for svc in $(oc --context "$CLUSTER_1_NAME" get svc -n "$CAMUNDA_NAMESPACE_1" -o jsonpath='{.items[*].metadata.name}'); do
    subctl --context "$CLUSTER_1_NAME" export service --namespace "$CAMUNDA_NAMESPACE_1" "$svc"
done

echo "Exporting services from $CLUSTER_2_NAME in $CAMUNDA_NAMESPACE_2 using subctl"

for svc in $(oc --context "$CLUSTER_2_NAME" get svc -n "$CAMUNDA_NAMESPACE_2" -o jsonpath='{.items[*].metadata.name}'); do
    subctl --context "$CLUSTER_2_NAME" export service --namespace "$CAMUNDA_NAMESPACE_2" "$svc"
done

# Wait for Submariner cross-cluster DNS readiness.
# The Lighthouse controller creates ServiceImport resources after export, then the
# Lighthouse CoreDNS plugin generates *.svc.clusterset.local DNS records.
# Without this wait, Zeebe brokers may fail to discover cross-cluster peers.

zeebe_svc="${CAMUNDA_RELEASE_NAME:-camunda}-zeebe"

wait_for_service_import() {
    local ctx=$1 ns=$2 elapsed=0
    echo "  Waiting for ServiceImport '${zeebe_svc}' in ${ctx}/${ns}..."
    until oc --context "$ctx" get serviceimport "${zeebe_svc}" -n "$ns" &>/dev/null; do
        elapsed=$((elapsed + 5))
        if [ "$elapsed" -ge "$DNS_WAIT_TIMEOUT" ]; then
            echo "  WARNING: ServiceImport not found after ${DNS_WAIT_TIMEOUT}s in ${ctx}/${ns}"
            return 0
        fi
        sleep 5
    done
    echo "  OK: ServiceImport '${zeebe_svc}' found in ${ctx}/${ns}"
}

echo ""
echo "Waiting for Submariner ServiceImport propagation (timeout: ${DNS_WAIT_TIMEOUT}s)..."
wait_for_service_import "$CLUSTER_1_NAME" "$CAMUNDA_NAMESPACE_1"
wait_for_service_import "$CLUSTER_2_NAME" "$CAMUNDA_NAMESPACE_2"

# Allow time for Lighthouse DNS records to propagate after ServiceImport creation
echo "  Waiting 15s for Lighthouse DNS propagation..."
sleep 15

echo "Service export and DNS propagation complete."

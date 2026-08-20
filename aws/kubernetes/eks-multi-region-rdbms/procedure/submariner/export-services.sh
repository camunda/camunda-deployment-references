#!/bin/bash
set -euo pipefail

# Exports the Camunda services of every active cluster to the Submariner
# ClusterSet, then waits for the resulting ServiceImports to appear.
#
# Only the services actually consumed across regions are exported, instead of
# every service in the namespace:
#   * <release>-zeebe          headless, carries Raft replication and the
#                              per-pod DNS records brokers dial each other on
#   * <release>-zeebe-gateway  gRPC entry point, lets a client in one region
#                              reach a gateway in another
#
# Re-run this after any operation that recreates services, for example after
# activating a new region.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"

DNS_WAIT_TIMEOUT="${DNS_WAIT_TIMEOUT:-300}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

services=(
    "${CAMUNDA_RELEASE_NAME}-zeebe"
    "${CAMUNDA_RELEASE_NAME}-zeebe-gateway"
)

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"

    for svc in "${services[@]}"; do
        if ! kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" get svc "$svc" >/dev/null 2>&1; then
            echo "  skipping $svc on $context: service does not exist (yet)"
            continue
        fi
        echo "Exporting $svc from $context"
        subctl --context "$context" export service --namespace "$CAMUNDA_NAMESPACE" "$svc"
    done
done

echo
echo "Waiting for Lighthouse ServiceImports to be published ..."

deadline=$((SECONDS + DNS_WAIT_TIMEOUT))
zeebe_svc="${CAMUNDA_RELEASE_NAME}-zeebe"

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    while ! kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" get serviceimport "$zeebe_svc" >/dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "WARNING: ServiceImport $zeebe_svc not visible on $context after ${DNS_WAIT_TIMEOUT}s." >&2
            echo "         Broker startup is gated on clusterset DNS anyway (see helm-values/camunda-values.yml)." >&2
            break
        fi
        sleep 5
    done
done

# Lighthouse publishes the DNS records shortly after the ServiceImport object.
sleep 15

echo "Exported services:"
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" get serviceexports.multicluster.x-k8s.io 2>/dev/null || true
done

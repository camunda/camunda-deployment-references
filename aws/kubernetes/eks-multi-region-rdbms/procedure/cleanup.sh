#!/bin/bash
set -euo pipefail

# Removes Camunda and Submariner from every active cluster.
#
# Run before `terraform destroy`: Camunda creates PVCs and load balancers that
# keep the VPC alive and make the destroy hang. Submariner is only the service
# discovery layer here, so it leaves no cloud resources behind, but uninstalling
# it keeps the broker registry from outliving the clusters.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    echo "Cleaning up $context"

    helm --kube-context "$context" --namespace "$CAMUNDA_NAMESPACE" \
        uninstall "$CAMUNDA_RELEASE_NAME" --wait --timeout 10m 2>/dev/null || true

    kubectl --context "$context" --namespace "$CAMUNDA_NAMESPACE" \
        delete pvc --all --wait=false 2>/dev/null || true

    # Removing the ServiceExports first stops Lighthouse from republishing
    # records while the Submariner components are torn down.
    kubectl --context "$context" --namespace "$CAMUNDA_NAMESPACE" \
        delete serviceexports.multicluster.x-k8s.io --all 2>/dev/null || true

    if command -v subctl >/dev/null 2>&1; then
        subctl uninstall --context "$context" --yes 2>/dev/null || true
    fi

    kubectl --context "$context" delete namespace "$CAMUNDA_NAMESPACE" --wait=false 2>/dev/null || true
done

echo "Cleanup complete. terraform destroy can now run."

#!/bin/bash
set -euo pipefail

# Script to install CloudNativePG operator for PostgreSQL
# Usage: ./01-postgresql-install-operator.sh [operator-namespace]

OPERATOR_NAMESPACE=${1:-cnpg-system}

echo "Installing CloudNativePG operator in namespace: $OPERATOR_NAMESPACE"

# Create namespace for the operator
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# TODo: in our official doc, mention usage of the official operator for OpenShift

# Install the operator
# TODO(renovate): manage CNPG manifest version via Renovate (auto-bump)

# Detect if we're running on OpenShift by checking node annotations
IS_OPENSHIFT=false
if kubectl get nodes -o jsonpath='{.items[0].metadata.annotations}' 2>/dev/null | grep -q "openshift"; then
    IS_OPENSHIFT=true
fi

# Install the operator with appropriate method
if [ "$IS_OPENSHIFT" = true ]; then
    echo "OpenShift detected - downloading and patching CloudNativePG manifest for SCC compatibility..."

    curl -s "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml" > /tmp/cnpg-manifest.yaml

    # Remove fixed UIDs/GIDs for OpenShift compatibility using a more targeted approach
    yq -i '(select(.kind == "Deployment" and .metadata.name == "cnpg-controller-manager") | .spec.template.spec.containers[].securityContext) |= del(.runAsUser, .runAsGroup)' /tmp/cnpg-manifest.yaml

    # Apply the modified manifest
    kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f /tmp/cnpg-manifest.yaml

    # Cleanup
    rm /tmp/cnpg-manifest.yaml

    echo "CloudNativePG installed with OpenShift SCC compatibility"
else
    # Standard Kubernetes - use original manifest
    kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
      "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml"

    echo "CloudNativePG installed for standard Kubernetes"
fi

echo "Waiting for operator to be ready..."
kubectl rollout status deployment \
  -n "$OPERATOR_NAMESPACE" cnpg-controller-manager

echo "CloudNativePG operator installed successfully!"

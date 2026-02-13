#!/bin/bash
# postgresql/deploy.sh - Deploy PostgreSQL via CloudNativePG operator
# Supports both standard Kubernetes and OpenShift (auto-detected)
#
# Environment variables:
#   CAMUNDA_NAMESPACE  - Target namespace (default: camunda)
#   CLUSTER_FILTER     - Optional: deploy only a specific cluster (e.g., "pg-keycloak")
#
# Arguments:
#   $1 - CNPG operator namespace (default: cnpg-system)

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
OPERATOR_NAMESPACE=${1:-cnpg-system}
CLUSTER_FILTER=${CLUSTER_FILTER:-}

# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="1.28.1"

# Auto-detect OpenShift by checking for the route.openshift.io API group
is_openshift() {
    kubectl api-resources --api-group=route.openshift.io >/dev/null 2>&1
}

CNPG_MANIFEST_URL="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-${CNPG_VERSION}.yaml"

# Install CloudNativePG operator
echo "Installing CloudNativePG operator v${CNPG_VERSION}..."

if ! is_openshift; then
    kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f "${CNPG_MANIFEST_URL}"
else
    # On OpenShift, the upstream manifest has hardcoded runAsUser/runAsGroup
    # that are rejected by the restricted-v2 SCC — download and patch them out
    echo "OpenShift detected - patching manifest for SCC compatibility..."
    curl -sL "${CNPG_MANIFEST_URL}" > /tmp/cnpg-manifest.yaml
    yq -i '(select(.kind == "Deployment" and .metadata.name == "cnpg-controller-manager") | .spec.template.spec.containers[].securityContext) |= del(.runAsUser, .runAsGroup)' /tmp/cnpg-manifest.yaml
    kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f /tmp/cnpg-manifest.yaml
    rm -f /tmp/cnpg-manifest.yaml
fi

# Wait for operator to be ready
kubectl rollout status deployment \
    -n "$OPERATOR_NAMESPACE" cnpg-controller-manager \
    --timeout=300s
echo "CloudNativePG operator deployed in namespace: $OPERATOR_NAMESPACE"

# Create PostgreSQL secrets
CAMUNDA_NAMESPACE="$CAMUNDA_NAMESPACE" "./set-secrets.sh"

# Deploy PostgreSQL clusters
echo "Deploying PostgreSQL clusters..."

if [[ -z "$CLUSTER_FILTER" ]]; then
    kubectl apply --server-side -f postgresql-clusters.yml -n "$CAMUNDA_NAMESPACE"
    kubectl wait --for=condition=Ready --timeout=600s cluster --all -n "$CAMUNDA_NAMESPACE"
else
    echo "Filtered deployment: $CLUSTER_FILTER only"
    yq "select(.metadata.name == \"$CLUSTER_FILTER\")" postgresql-clusters.yml | \
        kubectl apply -n "$CAMUNDA_NAMESPACE" --server-side -f -
    kubectl wait --for=condition=Ready --timeout=600s cluster "$CLUSTER_FILTER" -n "$CAMUNDA_NAMESPACE"
fi

echo "PostgreSQL deployment completed in namespace: $CAMUNDA_NAMESPACE"

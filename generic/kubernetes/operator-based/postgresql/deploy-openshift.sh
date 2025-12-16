#!/bin/bash
# postgresql/deploy.sh - Deploy PostgreSQL via CloudNativePG operator
# This version is modified to works with OpenShift and requires `yq`

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
OPERATOR_NAMESPACE=${1:-cnpg-system}

# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="1.28.0"

# Install CloudNativePG operator CRDs and operator
echo "OpenShift detected - downloading and patching CloudNativePG manifest for SCC compatibility..."

curl -s "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-${CNPG_VERSION}.yaml" > /tmp/cnpg-manifest.yaml

# Remove fixed UIDs/GIDs for OpenShift compatibility using a more targeted approach
yq -i '(select(.kind == "Deployment" and .metadata.name == "cnpg-controller-manager") | .spec.template.spec.containers[].securityContext) |= del(.runAsUser, .runAsGroup)' /tmp/cnpg-manifest.yaml

# Apply the modified manifest
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f /tmp/cnpg-manifest.yaml

# Cleanup
rm /tmp/cnpg-manifest.yaml

# Wait for operator to be ready
kubectl rollout status deployment \
  -n "$OPERATOR_NAMESPACE" cnpg-controller-manager \
  --timeout=300s
echo "CloudNativePG operator deployed in namespace: $OPERATOR_NAMESPACE"

# Create PostgreSQL secrets
CAMUNDA_NAMESPACE="$CAMUNDA_NAMESPACE" "./set-secrets.sh"

# Deploy PostgreSQL
kubectl apply -f "postgresql-clusters.yml" -n "$CAMUNDA_NAMESPACE"

# Wait for PostgreSQL cluster to be ready
kubectl wait --for=condition=Ready --timeout=600s cluster --all -n "$CAMUNDA_NAMESPACE"

echo "PostgreSQL deployment completed in namespace: $CAMUNDA_NAMESPACE"

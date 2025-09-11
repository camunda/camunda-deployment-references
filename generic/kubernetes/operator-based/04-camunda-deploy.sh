#!/bin/bash
set -euo pipefail

# Script to deploy Camunda Platform with operator-based infrastructure
# Usage: ./04-camunda-deploy.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Deploying Camunda Platform with operator-based infrastructure in namespace: $NAMESPACE"

# Check required environment variables
export CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
export CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}
export CAMUNDA_HELM_CHART_VERSION=${CAMUNDA_HELM_CHART_VERSION:-"0.0.0-snapshot-alpha"}

echo "Using CAMUNDA_DOMAIN: $CAMUNDA_DOMAIN"
echo "Using CAMUNDA_PROTOCOL: $CAMUNDA_PROTOCOL"
echo "Using CAMUNDA_HELM_CHART_VERSION: $CAMUNDA_HELM_CHART_VERSION"

# Verify envsubst is available
if ! command -v envsubst &> /dev/null; then
    echo "Error: envsubst is required but not installed"
    echo "On macOS: brew install gettext"
    echo "On Ubuntu/Debian: apt-get install gettext-base"
    exit 1
fi

# Verify helm is available
if ! command -v helm &> /dev/null; then
    echo "Error: helm is required but not installed"
    echo "Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Detect if we're running on OpenShift by checking node annotations
IS_OPENSHIFT=false
if kubectl get nodes -o jsonpath='{.items[0].metadata.annotations}' 2>/dev/null | grep -q "openshift"; then
    IS_OPENSHIFT=true
    echo "OpenShift detected - will configure chart for OpenShift compatibility"
else
    echo "Standard Kubernetes detected"
fi

# Add Camunda Helm repository if not already added (for fallback)
if ! helm repo list | grep -q "camunda"; then
    echo "Adding Camunda Helm repository..."
    helm repo add camunda https://helm.camunda.io
fi

echo "Updating Helm repositories..."
helm repo update

# Apply environment variable substitution to values file
echo "Applying environment variable substitution to values file..."
envsubst < values-operator-based.yml > values-operator-based-final.yml

# Prepare OpenShift-specific parameters
EXTRA_ARGS=""
if [ "$IS_OPENSHIFT" = true ]; then
    echo "Adding OpenShift compatibility settings..."
    EXTRA_ARGS="--set global.compatibility.openshift.adaptSecurityContext=force"
fi

# Install or upgrade Camunda Platform using OCI registry
echo "Installing/upgrading Camunda Platform from OCI registry..."
helm upgrade --install camunda oci://ghcr.io/camunda/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --values values-operator-based-final.yml \
    "$EXTRA_ARGS" \
    --wait \
    --timeout 10m

# Alternative installation using traditional Helm repo (commented out)
# helm upgrade --install camunda camunda/camunda-platform \
#     --version "$CAMUNDA_HELM_CHART_VERSION" \
#     --namespace "$NAMESPACE" \
#     --create-namespace \
#     --values values-operator-based-final.yml \
#     "$EXTRA_ARGS" \
#     --wait \
#     --timeout 10m

# Clean up temporary file
rm -f values-operator-based-final.yml

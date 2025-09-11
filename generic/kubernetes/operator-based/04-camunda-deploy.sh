#!/bin/bash
set -euo pipefail

# Script to deploy Camunda Platform with operator-based infrastructure
# Usage: ./04-camunda-deploy.sh [namespace]

NAMESPACE=${1:-${CAMUNDA_NAMESPACE:-camunda}}

echo "Deploying Camunda Platform with operator-based infrastructure in namespace: $NAMESPACE"

# Check required environment variables
export CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
export CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}
export CAMUNDA_HELM_CHART_VERSION=${CAMUNDA_HELM_CHART_VERSION:-"0.0.0-snapshot-alpha"}

echo "Using CAMUNDA_DOMAIN: $CAMUNDA_DOMAIN"
echo "Using CAMUNDA_PROTOCOL: $CAMUNDA_PROTOCOL"
echo "Using CAMUNDA_HELM_CHART_VERSION: $CAMUNDA_HELM_CHART_VERSION"

# Verify required tools are available
if ! command -v envsubst &> /dev/null; then
    echo "Error: envsubst is required but not installed"
    echo "On macOS: brew install gettext"
    echo "On Ubuntu/Debian: apt-get install gettext-base"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "Error: helm is required but not installed"
    echo "Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    echo "On macOS: brew install yq"
    echo "On Ubuntu/Debian: snap install yq"
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

# Choose values file and configure ingress settings based on domain and platform
VALUES_FILE="values-operator-based.yml"
export INGRESS_CLASS_NAME="nginx"

echo "Preparing Camunda configuration..."
cp "$VALUES_FILE" values-operator-based-temp.yml

if [ "$CAMUNDA_DOMAIN" != "localhost" ]; then
    echo "Enabling ingress for domain: $CAMUNDA_DOMAIN"

    # Enable global ingress
    yq eval '.global.ingress.enabled = true' -i values-operator-based-temp.yml

    if [ "$IS_OPENSHIFT" = true ]; then
        export INGRESS_CLASS_NAME="openshift-default"
        echo "Using OpenShift ingress class: $INGRESS_CLASS_NAME"
        # Update TLS settings for OpenShift
        yq eval '.global.ingress.annotations."route.openshift.io/termination" = "edge"' -i values-operator-based-temp.yml
    else
        export INGRESS_CLASS_NAME="nginx"
        echo "Using Nginx ingress class: $INGRESS_CLASS_NAME"
    fi
else
    echo "Using basic configuration for localhost (port-forward access)"
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
envsubst < values-operator-based-temp.yml > values-operator-based-final.yml

# Prepare OpenShift-specific parameters
EXTRA_ARGS=()
if [ "$IS_OPENSHIFT" = true ]; then
    echo "Adding OpenShift compatibility settings..."
    EXTRA_ARGS+=(--set global.compatibility.openshift.adaptSecurityContext=force)
fi

# Install or upgrade Camunda Platform using OCI registry
echo "Installing/upgrading Camunda Platform from OCI registry..."
helm upgrade --install camunda oci://ghcr.io/camunda/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --values values-operator-based-final.yml \
    "${EXTRA_ARGS[@]}" \
    --wait \
    --timeout 10m

# Alternative installation using traditional Helm repo (commented out)
# helm upgrade --install camunda camunda/camunda-platform \
#     --version "$CAMUNDA_HELM_CHART_VERSION" \
#     --namespace "$NAMESPACE" \
#     --create-namespace \
#     --values values-operator-based-final.yml \
#     "${EXTRA_ARGS[@]}" \
#     --wait \
#     --timeout 10m

# Clean up temporary files
rm -f values-operator-based-temp.yml values-operator-based-final.yml

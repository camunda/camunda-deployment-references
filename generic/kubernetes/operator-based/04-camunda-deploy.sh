#!/bin/bash
set -euo pipefail

# Script to deploy Camunda Platform with operator-based infrastructure
# Usage: ./04-camunda-deploy.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Deploying Camunda Platform with operator-based infrastructure in namespace: $NAMESPACE"

# Check required environment variables
export CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
export CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}

echo "Using CAMUNDA_DOMAIN: $CAMUNDA_DOMAIN"
echo "Using CAMUNDA_PROTOCOL: $CAMUNDA_PROTOCOL"

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

# Add Camunda Helm repository if not already added
if ! helm repo list | grep -q "camunda"; then
    echo "Adding Camunda Helm repository..."
    helm repo add camunda https://helm.camunda.io
fi

echo "Updating Helm repositories..."
helm repo update

# Apply environment variable substitution to values file
echo "Applying environment variable substitution to values file..."
envsubst < values-operator-based.yml > values-operator-based-final.yml

# Install or upgrade Camunda Platform
echo "Installing/upgrading Camunda Platform..."
helm upgrade --install camunda camunda/camunda-platform \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --values values-operator-based-final.yml \
    --wait \
    --timeout 10m

echo "Camunda Platform deployment completed!"
echo "Namespace: $NAMESPACE"
echo "Access URL: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}"

# Clean up temporary file
rm -f values-operator-based-final.yml

echo ""
echo "Next steps:"
echo "1. Configure Keycloak realm using admin credentials:"
echo "   ./03-keycloak-get-admin-credentials.sh $NAMESPACE"
echo "2. Access Keycloak admin console: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/"
echo "3. The Camunda Platform will automatically configure the required realm and clients"

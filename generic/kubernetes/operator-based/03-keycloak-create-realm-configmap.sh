#!/bin/bash
set -euo pipefail

# Script to create Keycloak realm ConfigMap with templated realm configuration
# Usage: ./03-keycloak-create-realm-configmap.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Creating Keycloak realm ConfigMap in namespace: $NAMESPACE"

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

# Check if the realm file exists
if [[ ! -f "realm-camunda-platform.json" ]]; then
    echo "Error: realm-camunda-platform.json not found!"
    exit 1
fi

# Check if secrets exist for environment variable values
if ! kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Error: Secret 'keycloak-realm-secrets' not found in namespace $NAMESPACE"
    echo "Please run: ./03-keycloak-create-realm-secrets.sh $NAMESPACE"
    exit 1
fi

echo "✓ Keycloak realm secrets found"

# Get all the client secrets from the Kubernetes secret
echo "Retrieving client secrets from Kubernetes secret..."

export KC_IDENTITY_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_IDENTITY_CLIENT_SECRET}' | base64 --decode)
export KC_IDENTITY_RESOURCE_SERVER_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_IDENTITY_RESOURCE_SERVER_CLIENT_SECRET}' | base64 --decode)
export KC_CONNECTORS_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_CONNECTORS_CLIENT_SECRET}' | base64 --decode)
export KC_CONSOLE_API_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_CONSOLE_API_CLIENT_SECRET}' | base64 --decode)
export KC_OPERATE_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_OPERATE_CLIENT_SECRET}' | base64 --decode)
export KC_OPERATE_API_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_OPERATE_API_CLIENT_SECRET}' | base64 --decode)
export KC_OPTIMIZE_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_OPTIMIZE_CLIENT_SECRET}' | base64 --decode)
export KC_OPTIMIZE_API_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_OPTIMIZE_API_CLIENT_SECRET}' | base64 --decode)
export KC_TASKLIST_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_TASKLIST_CLIENT_SECRET}' | base64 --decode)
export KC_TASKLIST_API_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_TASKLIST_API_CLIENT_SECRET}' | base64 --decode)
export KC_WEB_MODELER_API_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_WEB_MODELER_API_CLIENT_SECRET}' | base64 --decode)
export KC_WEB_MODELER_PUBLIC_API_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_WEB_MODELER_PUBLIC_API_CLIENT_SECRET}' | base64 --decode)
export KC_ZEEBE_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_ZEEBE_CLIENT_SECRET}' | base64 --decode)
export KC_ZEEBE_API_CLIENT_SECRET=$(kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" -o jsonpath='{.data.KC_ZEEBE_API_CLIENT_SECRET}' | base64 --decode)

# Process the realm template with envsubst to replace all variables
echo "Processing realm template with environment variables..."
TEMP_REALM=$(mktemp)
envsubst < realm-camunda-platform.json > "$TEMP_REALM"

# Delete existing ConfigMap if it exists
if kubectl get configmap keycloak-realm-config -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Deleting existing ConfigMap keycloak-realm-config..."
    kubectl delete configmap keycloak-realm-config -n "$NAMESPACE"
fi

# Create the ConfigMap with the processed realm file
echo "Creating ConfigMap keycloak-realm-config..."
kubectl create configmap keycloak-realm-config -n "$NAMESPACE" \
    --from-file=realm-camunda-platform.json="$TEMP_REALM"

# Clean up temp file
rm "$TEMP_REALM"

echo "ConfigMap 'keycloak-realm-config' created successfully!"
echo "The ConfigMap contains the fully templated realm configuration."
echo "Keycloak will automatically import this realm on startup."

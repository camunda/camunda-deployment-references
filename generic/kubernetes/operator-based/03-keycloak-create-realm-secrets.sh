#!/bin/bash
set -euo pipefail

# Script to create Keycloak realm secrets for Camunda client secrets
# Usage: ./03-keycloak-create-realm-secrets.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Creating Keycloak realm secrets in namespace: $NAMESPACE"

# Function to generate a random secret (32 characters)
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Check if secret already exists
if kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Secret keycloak-realm-secrets already exists in namespace $NAMESPACE"
    echo "Delete it first if you want to regenerate: kubectl delete secret keycloak-realm-secrets -n $NAMESPACE"
    exit 0
fi

echo "Generating random client secrets..."

# Generate all the client secrets
KC_IDENTITY_CLIENT_SECRET=$(generate_secret)
KC_IDENTITY_RESOURCE_SERVER_CLIENT_SECRET=$(generate_secret)
KC_CONNECTORS_CLIENT_SECRET=$(generate_secret)
KC_CONSOLE_API_CLIENT_SECRET=$(generate_secret)
KC_OPERATE_CLIENT_SECRET=$(generate_secret)
KC_OPERATE_API_CLIENT_SECRET=$(generate_secret)
KC_OPTIMIZE_CLIENT_SECRET=$(generate_secret)
KC_OPTIMIZE_API_CLIENT_SECRET=$(generate_secret)
KC_TASKLIST_CLIENT_SECRET=$(generate_secret)
KC_TASKLIST_API_CLIENT_SECRET=$(generate_secret)
KC_WEB_MODELER_API_CLIENT_SECRET=$(generate_secret)
KC_WEB_MODELER_PUBLIC_API_CLIENT_SECRET=$(generate_secret)
KC_ZEEBE_CLIENT_SECRET=$(generate_secret)
KC_ZEEBE_API_CLIENT_SECRET=$(generate_secret)

# Get domain and protocol with defaults
CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}

echo "Using CAMUNDA_DOMAIN: $CAMUNDA_DOMAIN"
echo "Using CAMUNDA_PROTOCOL: $CAMUNDA_PROTOCOL"

# Create the secret with all client secrets and domain/protocol
kubectl create secret generic keycloak-realm-secrets -n "$NAMESPACE" \
    --from-literal=KC_IDENTITY_CLIENT_SECRET="$KC_IDENTITY_CLIENT_SECRET" \
    --from-literal=KC_IDENTITY_RESOURCE_SERVER_CLIENT_SECRET="$KC_IDENTITY_RESOURCE_SERVER_CLIENT_SECRET" \
    --from-literal=KC_CONNECTORS_CLIENT_SECRET="$KC_CONNECTORS_CLIENT_SECRET" \
    --from-literal=KC_CONSOLE_API_CLIENT_SECRET="$KC_CONSOLE_API_CLIENT_SECRET" \
    --from-literal=KC_OPERATE_CLIENT_SECRET="$KC_OPERATE_CLIENT_SECRET" \
    --from-literal=KC_OPERATE_API_CLIENT_SECRET="$KC_OPERATE_API_CLIENT_SECRET" \
    --from-literal=KC_OPTIMIZE_CLIENT_SECRET="$KC_OPTIMIZE_CLIENT_SECRET" \
    --from-literal=KC_OPTIMIZE_API_CLIENT_SECRET="$KC_OPTIMIZE_API_CLIENT_SECRET" \
    --from-literal=KC_TASKLIST_CLIENT_SECRET="$KC_TASKLIST_CLIENT_SECRET" \
    --from-literal=KC_TASKLIST_API_CLIENT_SECRET="$KC_TASKLIST_API_CLIENT_SECRET" \
    --from-literal=KC_WEB_MODELER_API_CLIENT_SECRET="$KC_WEB_MODELER_API_CLIENT_SECRET" \
    --from-literal=KC_WEB_MODELER_PUBLIC_API_CLIENT_SECRET="$KC_WEB_MODELER_PUBLIC_API_CLIENT_SECRET" \
    --from-literal=KC_ZEEBE_CLIENT_SECRET="$KC_ZEEBE_CLIENT_SECRET" \
    --from-literal=KC_ZEEBE_API_CLIENT_SECRET="$KC_ZEEBE_API_CLIENT_SECRET" \
    --from-literal=CAMUNDA_DOMAIN="$CAMUNDA_DOMAIN" \
    --from-literal=CAMUNDA_PROTOCOL="$CAMUNDA_PROTOCOL"

echo "Secret 'keycloak-realm-secrets' created successfully with all client secrets!"
echo "The secret contains:"
echo "  - Client secrets (KC_*_CLIENT_SECRET)"
echo "  - CAMUNDA_DOMAIN: $CAMUNDA_DOMAIN"
echo "  - CAMUNDA_PROTOCOL: $CAMUNDA_PROTOCOL"

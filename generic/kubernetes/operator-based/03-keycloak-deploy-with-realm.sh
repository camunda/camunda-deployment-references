#!/bin/bash
set -euo pipefail

# Script to deploy Keycloak with realm auto-import via Secret
# Usage: ./03-keycloak-deploy-with-realm.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Deploying Keycloak with realm auto-import in namespace: $NAMESPACE"

# Check required environment variables
export CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-localhost}
export CAMUNDA_PROTOCOL=${CAMUNDA_PROTOCOL:-http}

echo "Using CAMUNDA_DOMAIN: $CAMUNDA_DOMAIN"
echo "Using CAMUNDA_PROTOCOL: $CAMUNDA_PROTOCOL"

# Check if secrets exist
if ! kubectl get secret keycloak-realm-secrets -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Error: Secret 'keycloak-realm-secrets' not found in namespace $NAMESPACE"
    echo "Please run: ./03-keycloak-create-realm-secrets.sh $NAMESPACE"
    exit 1
fi

echo "✓ Keycloak realm secrets found"

# Create the realm Secret
echo "=== Creating Keycloak Realm Secret ==="
./03-keycloak-create-realm-secret.sh "$NAMESPACE"

# Deploy Keycloak instance with Secret mount
echo "=== Deploying Keycloak Instance with Realm Mount ==="
envsubst < 03-keycloak-instance.yml | kubectl apply -n "$NAMESPACE" -f -

echo "Keycloak deployment with realm auto-import completed!"
echo "Keycloak will automatically import the realm on startup."
echo "Access URL: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/"

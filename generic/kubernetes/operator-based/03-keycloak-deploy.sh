#!/bin/bash
set -euo pipefail

# Script to deploy Keycloak instance with environment variable substitution
# Usage: ./03-keycloak-deploy.sh [namespace]

NAMESPACE=${1:-camunda}

echo "Deploying Keycloak in namespace: $NAMESPACE"

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

# Deploy Keycloak instance with variable substitution
echo "Deploying Keycloak instance..."
envsubst < 03-keycloak-instance.yml | kubectl apply -n "$NAMESPACE" -f -

# Deploy Keycloak ingress with variable substitution
echo "Deploying Keycloak ingress..."
envsubst < 03-keycloak-ingress.yml | kubectl apply -n "$NAMESPACE" -f -

echo "Keycloak deployment completed!"
echo "Access URL: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/"

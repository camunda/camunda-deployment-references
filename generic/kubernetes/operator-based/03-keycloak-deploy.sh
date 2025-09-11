#!/bin/bash
set -euo pipefail

# Script to deploy Keycloak instance with environment variable substitution
# Usage: ./03-keycloak-deploy.sh [namespace]

NAMESPACE=${1:-${CAMUNDA_NAMESPACE:-camunda}}

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

# Detect if we're running on OpenShift by checking node annotations
IS_OPENSHIFT=false
if kubectl get nodes -o jsonpath='{.items[0].metadata.annotations}' 2>/dev/null | grep -q "openshift"; then
    IS_OPENSHIFT=true
    echo "OpenShift detected"
else
    echo "Standard Kubernetes detected"
fi

# Choose deployment configuration based on domain and platform
KEYCLOAK_CONFIG="03-keycloak-instance.yml"
if [ "$CAMUNDA_DOMAIN" != "localhost" ]; then
    if [ "$IS_OPENSHIFT" = true ]; then
        KEYCLOAK_CONFIG="03-keycloak-instance-openshift.yml"
        echo "Using OpenShift ingress configuration for domain: $CAMUNDA_DOMAIN"
    else
        KEYCLOAK_CONFIG="03-keycloak-instance-ingress.yml"
        echo "Using Nginx ingress configuration for domain: $CAMUNDA_DOMAIN"
    fi
else
    echo "Using basic configuration for localhost (port-forward access)"
fi

# Deploy Keycloak instance with variable substitution
echo "Deploying Keycloak instance using: $KEYCLOAK_CONFIG"
envsubst < "$KEYCLOAK_CONFIG" | kubectl apply -n "$NAMESPACE" -f -

echo "Keycloak deployment completed!"
if [ "$CAMUNDA_DOMAIN" != "localhost" ]; then
    echo "Access URL: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/"
else
    echo "Access URL: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/ (via port-forward)"
    echo "To enable port-forward: kubectl port-forward svc/keycloak-service 8080:8080 -n $NAMESPACE"
fi

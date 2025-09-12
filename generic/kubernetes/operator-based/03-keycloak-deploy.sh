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

# Verify required tools are available
if ! command -v envsubst &> /dev/null; then
    echo "Error: envsubst is required but not installed"
    echo "On macOS: brew install gettext"
    echo "On Ubuntu/Debian: apt-get install gettext-base"
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
    echo "OpenShift detected"
else
    echo "Standard Kubernetes detected"
fi

# Start with base configuration
echo "Preparing Keycloak configuration..."
cp 03-keycloak-instance.yml keycloak-temp.yml

# Configure ingress based on domain and platform
if [ "$CAMUNDA_DOMAIN" != "localhost" ]; then
    echo "Enabling ingress for domain: $CAMUNDA_DOMAIN"
    yq eval '.spec.ingress.enabled = true' -i keycloak-temp.yml

    # Enable TLS and backchannel for ingress deployments
    yq eval '.spec.hostname.tlsSecret = "camunda-keycloak-tls"' -i keycloak-temp.yml
    yq eval '.spec.hostname.backchannelDynamic = true' -i keycloak-temp.yml

    if [ "$IS_OPENSHIFT" = true ]; then
        echo "Configuring for OpenShift ingress"
        export INGRESS_CLASS_NAME="openshift-default"
        yq eval '.spec.ingress.annotations."route.openshift.io/termination" = "edge"' -i keycloak-temp.yml
        yq eval '.spec.ingress.rules[0].paths[0].path = "/auth"' -i keycloak-temp.yml
    else
        echo "Configuring for Nginx ingress"
        export INGRESS_CLASS_NAME="nginx"
    fi
else
    echo "Using basic configuration for localhost (port-forward access)"
fi

# Deploy Keycloak instance with variable substitution
echo "Deploying Keycloak instance..."
export INGRESS_CLASS_NAME=${INGRESS_CLASS_NAME:-nginx}
envsubst < keycloak-temp.yml | kubectl apply -n "$NAMESPACE" -f -

# Clean up temporary file
rm -f keycloak-temp.yml

echo "Keycloak deployment completed!"
if [ "$CAMUNDA_DOMAIN" != "localhost" ]; then
    echo "Access URL: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/"
else
    echo "Access URL: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/ (via port-forward)"
    echo "To enable port-forward: kubectl port-forward svc/keycloak-service 8080:8080 -n $NAMESPACE"
fi

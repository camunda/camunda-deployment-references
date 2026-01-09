#!/bin/bash
# Create Kubernetes secrets for Amazon Cognito authentication
# Retrieves secrets from AWS Secrets Manager and creates Kubernetes secrets

set -euo pipefail

# Check required environment variables
if [ -z "${CAMUNDA_NAMESPACE:-}" ]; then
    echo "Error: CAMUNDA_NAMESPACE is not set"
    exit 1
fi

if [ -z "${COGNITO_SECRET_NAME:-}" ]; then
    echo "Error: COGNITO_SECRET_NAME is not set"
    echo "Run: source procedure/vars-cognito.sh first"
    exit 1
fi

echo "Retrieving Cognito credentials from AWS Secrets Manager..."

# Get secret from AWS Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$COGNITO_SECRET_NAME" \
    --query 'SecretString' \
    --output text)

# Extract values
IDENTITY_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.identity_client_secret')
OPTIMIZE_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.optimize_client_secret')
ORCHESTRATION_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.orchestration_client_secret')
CONNECTORS_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.connectors_client_secret')
WEBMODELER_API_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.webmodeler_api_client_secret // empty')

echo "Creating Cognito secrets in namespace: $CAMUNDA_NAMESPACE"

# Ensure namespace exists
kubectl create namespace "$CAMUNDA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Identity secret
kubectl create secret generic camunda-cognito-identity-secret \
    --namespace "$CAMUNDA_NAMESPACE" \
    --from-literal=client-secret="$IDENTITY_CLIENT_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -
echo "Created Identity secret"

# Optimize secret
kubectl create secret generic camunda-cognito-optimize-secret \
    --namespace "$CAMUNDA_NAMESPACE" \
    --from-literal=client-secret="$OPTIMIZE_CLIENT_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -
echo "Created Optimize secret"

# Orchestration secret
kubectl create secret generic camunda-cognito-orchestration-secret \
    --namespace "$CAMUNDA_NAMESPACE" \
    --from-literal=client-secret="$ORCHESTRATION_CLIENT_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -
echo "Created Orchestration secret"

# Connectors secret
kubectl create secret generic camunda-cognito-connectors-secret \
    --namespace "$CAMUNDA_NAMESPACE" \
    --from-literal=client-secret="$CONNECTORS_CLIENT_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -
echo "Created Connectors secret"

# WebModeler API secret (optional)
if [ -n "$WEBMODELER_API_CLIENT_SECRET" ]; then
    kubectl create secret generic camunda-cognito-webmodeler-api-secret \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-literal=client-secret="$WEBMODELER_API_CLIENT_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created WebModeler API secret"
fi

echo ""
echo "Cognito secrets created successfully from AWS Secrets Manager"

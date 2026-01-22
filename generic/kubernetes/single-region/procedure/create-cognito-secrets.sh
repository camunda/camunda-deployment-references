#!/bin/bash
# Create Kubernetes secrets for AWS Cognito OIDC authentication
# For testing: retrieves secrets from Cognito outputs
# For production: users should provide their own credentials

set -euo pipefail

# Check required environment variables
if [ -z "${CAMUNDA_NAMESPACE:-}" ]; then
    echo "Error: CAMUNDA_NAMESPACE is not set"
    exit 1
fi

echo "Creating Cognito OIDC secrets in namespace: $CAMUNDA_NAMESPACE"

# Ensure namespace exists
kubectl create namespace "$CAMUNDA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Check if we're in test mode (Cognito outputs) or production mode (user-provided)
if [ -n "${COGNITO_IDENTITY_CLIENT_SECRET:-}" ]; then
    echo "📝 Using provided Cognito credentials (test mode or environment variables)"

    # Identity secret
    kubectl create secret generic camunda-cognito-identity-secret \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-literal=client-secret="${COGNITO_IDENTITY_CLIENT_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ Created Identity secret"

    # Optimize secret
    if [ -n "${COGNITO_OPTIMIZE_CLIENT_SECRET:-}" ]; then
        kubectl create secret generic camunda-cognito-optimize-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${COGNITO_OPTIMIZE_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Optimize secret"
    fi

    # Orchestration secret
    if [ -n "${COGNITO_ORCHESTRATION_CLIENT_SECRET:-}" ]; then
        kubectl create secret generic camunda-cognito-orchestration-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${COGNITO_ORCHESTRATION_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Orchestration secret"
    fi

    # Connectors secret
    if [ -n "${COGNITO_CONNECTORS_CLIENT_SECRET:-}" ]; then
        kubectl create secret generic camunda-cognito-connectors-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${COGNITO_CONNECTORS_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Connectors secret"
    fi

    # Web Modeler secret (optional)
    if [ -n "${COGNITO_WEBMODELER_API_CLIENT_SECRET:-}" ] && [ "${WEBMODELER_ENABLED:-false}" == "true" ]; then
        kubectl create secret generic camunda-cognito-webmodeler-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${COGNITO_WEBMODELER_API_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Web Modeler secret"
    fi

else
    echo "⚠️  No Cognito credentials found in environment variables"
    echo ""
    echo "Please set the following environment variables:"
    echo "  - COGNITO_IDENTITY_CLIENT_SECRET"
    echo "  - COGNITO_OPTIMIZE_CLIENT_SECRET"
    echo "  - COGNITO_ORCHESTRATION_CLIENT_SECRET"
    echo "  - COGNITO_CONNECTORS_CLIENT_SECRET"
    echo "  - COGNITO_WEBMODELER_API_CLIENT_SECRET (if Web Modeler is enabled)"
    echo ""
    echo "Or create the secrets manually:"
    echo ""
    echo "kubectl create secret generic camunda-cognito-identity-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-identity-secret'"
    echo ""
    echo "kubectl create secret generic camunda-cognito-optimize-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-optimize-secret'"
    echo ""
    echo "kubectl create secret generic camunda-cognito-orchestration-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-orchestration-secret'"
    echo ""
    echo "kubectl create secret generic camunda-cognito-connectors-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-connectors-secret'"
    echo ""
    exit 1
fi

echo ""
echo "✅ All Cognito OIDC secrets created successfully"
echo ""
echo "To verify secrets:"
echo "kubectl get secrets -n ${CAMUNDA_NAMESPACE} | grep cognito"

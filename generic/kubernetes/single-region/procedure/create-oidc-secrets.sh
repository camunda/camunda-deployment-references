#!/bin/bash
# Create Kubernetes secrets for external OIDC provider authentication
# For testing: retrieves secrets from EntraID outputs
# For production: users should provide their own OIDC credentials

set -euo pipefail

# Check required environment variables
if [ -z "${CAMUNDA_NAMESPACE:-}" ]; then
    echo "Error: CAMUNDA_NAMESPACE is not set"
    exit 1
fi

echo "Creating OIDC secrets in namespace: $CAMUNDA_NAMESPACE"

# Ensure namespace exists
kubectl create namespace "$CAMUNDA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Check if we're in test mode (EntraID) or production mode (user-provided)
if [ -n "${OIDC_IDENTITY_CLIENT_SECRET:-}" ]; then
    echo "📝 Using provided OIDC credentials (test mode or environment variables)"

    # Identity secret
    kubectl create secret generic camunda-oidc-identity-secret \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-literal=client-secret="${OIDC_IDENTITY_CLIENT_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ Created Identity secret"

    # Optimize secret
    if [ -n "${OIDC_OPTIMIZE_CLIENT_SECRET:-}" ]; then
        kubectl create secret generic camunda-oidc-optimize-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${OIDC_OPTIMIZE_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Optimize secret"
    fi

    # Orchestration secret
    if [ -n "${OIDC_ORCHESTRATION_CLIENT_SECRET:-}" ]; then
        kubectl create secret generic camunda-oidc-orchestration-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${OIDC_ORCHESTRATION_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Orchestration secret"
    fi

    # Connectors secret
    if [ -n "${OIDC_CONNECTORS_CLIENT_SECRET:-}" ]; then
        kubectl create secret generic camunda-oidc-connectors-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${OIDC_CONNECTORS_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Connectors secret"
    fi

    # Web Modeler secret (optional)
    if [ -n "${OIDC_WEBMODELER_API_CLIENT_SECRET:-}" ] && [ "${WEBMODELER_ENABLED:-false}" == "true" ]; then
        kubectl create secret generic camunda-oidc-webmodeler-secret \
            --namespace "$CAMUNDA_NAMESPACE" \
            --from-literal=client-secret="${OIDC_WEBMODELER_API_CLIENT_SECRET}" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "✅ Created Web Modeler secret"
    fi

else
    echo "⚠️  No OIDC credentials found in environment variables"
    echo ""
    echo "Please set the following environment variables:"
    echo "  - OIDC_IDENTITY_CLIENT_SECRET"
    echo "  - OIDC_OPTIMIZE_CLIENT_SECRET"
    echo "  - OIDC_ORCHESTRATION_CLIENT_SECRET"
    echo "  - OIDC_CONNECTORS_CLIENT_SECRET"
    echo "  - OIDC_WEBMODELER_API_CLIENT_SECRET (if Web Modeler is enabled)"
    echo ""
    echo "Or create the secrets manually:"
    echo ""
    echo "kubectl create secret generic camunda-oidc-identity-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-identity-secret'"
    echo ""
    echo "kubectl create secret generic camunda-oidc-optimize-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-optimize-secret'"
    echo ""
    echo "kubectl create secret generic camunda-oidc-orchestration-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-orchestration-secret'"
    echo ""
    echo "kubectl create secret generic camunda-oidc-connectors-secret \\"
    echo "    --namespace ${CAMUNDA_NAMESPACE} \\"
    echo "    --from-literal=client-secret='your-connectors-secret'"
    echo ""
    exit 1
fi

echo ""
echo "✅ All OIDC secrets created successfully"
echo ""
echo "To verify secrets:"
echo "kubectl get secrets -n ${CAMUNDA_NAMESPACE} | grep oidc"

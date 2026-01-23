#!/bin/bash
# Create Kubernetes secrets for external OIDC authentication

set -euo pipefail

if [ -z "${OIDC_IDENTITY_CLIENT_SECRET:-}" ]; then
    echo "⚠️  No OIDC credentials found in environment variables"
    echo ""
    echo "Please set the following environment variables:"
    echo "  - OIDC_IDENTITY_CLIENT_SECRET (required)"
    echo "  - OIDC_OPTIMIZE_CLIENT_SECRET"
    echo "  - OIDC_ORCHESTRATION_CLIENT_SECRET"
    echo "  - OIDC_CONNECTORS_CLIENT_SECRET"
    echo "  - OIDC_WEBMODELER_API_CLIENT_SECRET (if Web Modeler is enabled)"
    exit 1
fi

echo "📝 Creating OIDC secret..."

kubectl create secret generic camunda-oidc-secrets \
    --namespace "$CAMUNDA_NAMESPACE" \
    --from-literal=identity-client-secret="${OIDC_IDENTITY_CLIENT_SECRET}" \
    --from-literal=optimize-client-secret="${OIDC_OPTIMIZE_CLIENT_SECRET:-}" \
    --from-literal=orchestration-client-secret="${OIDC_ORCHESTRATION_CLIENT_SECRET:-}" \
    --from-literal=connectors-client-secret="${OIDC_CONNECTORS_CLIENT_SECRET:-}" \
    --from-literal=webmodeler-api-client-secret="${OIDC_WEBMODELER_API_CLIENT_SECRET:-}" \
    --from-literal=smtp-password="${SMTP_PASSWORD:-}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Created camunda-oidc-secrets with all OIDC client credentials"
echo ""
echo "To verify:"
echo "  kubectl get secret camunda-oidc-secrets -n ${CAMUNDA_NAMESPACE} -o yaml"

#!/bin/bash
# Create secrets for EntraID authentication according to Camunda documentation
# https://docs.camunda.io/docs/self-managed/deployment/helm/configure/authentication-and-authorization/microsoft-entra/
# These values should be exported from Terraform outputs using export-entraid-vars.sh

set -euo pipefail

CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}

# Check required environment variables for OIDC client secrets
required_vars=(
    "IDENTITY_CLIENT_SECRET"
    "ORCHESTRATION_CLIENT_SECRET"
    "OPTIMIZE_CLIENT_SECRET"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "Error: Required environment variable $var is not set"
        echo "Please run: source ./export-entraid-vars.sh"
        exit 1
    fi
done

echo "Creating EntraID OIDC client secrets in namespace: $CAMUNDA_NAMESPACE..."

# Create secret with all OIDC client secrets as per Camunda documentation
kubectl create secret generic entra-credentials \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=identity-client-secret="$IDENTITY_CLIENT_SECRET" \
  --from-literal=orchestration-cluster-client-secret="$ORCHESTRATION_CLIENT_SECRET" \
  --from-literal=optimize-client-secret="$OPTIMIZE_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# Add WebModeler API secret if enabled (WebModeler UI is a SPA and doesn't need a secret)
if [ -n "${WEBMODELER_API_CLIENT_SECRET:-}" ]; then
    echo "Adding WebModeler API credentials to secret..."
    kubectl create secret generic entra-credentials \
      --namespace "$CAMUNDA_NAMESPACE" \
      --from-literal=identity-client-secret="$IDENTITY_CLIENT_SECRET" \
      --from-literal=orchestration-cluster-client-secret="$ORCHESTRATION_CLIENT_SECRET" \
      --from-literal=optimize-client-secret="$OPTIMIZE_CLIENT_SECRET" \
      --from-literal=webmodeler-api-client-secret="$WEBMODELER_API_CLIENT_SECRET" \
      --dry-run=client -o yaml | kubectl apply -f -
fi

echo ""
echo "✅ EntraID OIDC client secrets created successfully!"
echo ""
echo "Note: Console and WebModeler UI are Single Page Applications"
echo "      and do not require client secrets."

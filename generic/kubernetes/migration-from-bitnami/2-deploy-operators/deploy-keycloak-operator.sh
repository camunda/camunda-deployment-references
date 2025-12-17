#!/bin/bash

# =============================================================================
# Deploy Keycloak Operator
# =============================================================================
# Deploys the Keycloak operator for identity management
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../0-set-environment.sh" 2>/dev/null || true

echo "============================================="
echo "Deploying Keycloak Operator"
echo "============================================="
echo ""
echo "Version: ${KEYCLOAK_VERSION}"
echo "Namespace: ${CAMUNDA_NAMESPACE}"
echo ""

# Install Keycloak operator CRDs
echo "Installing Keycloak CRDs..."
kubectl apply --server-side -f \
    "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/keycloaks.k8s.keycloak.org-v1.yml"
kubectl apply --server-side -f \
    "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml"

# Install Keycloak operator in Camunda namespace
echo ""
echo "Installing Keycloak operator..."
kubectl apply -n "$CAMUNDA_NAMESPACE" --server-side -f \
    "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/kubernetes.yml"

# Wait for operator to be ready
echo ""
echo "Waiting for operator to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/keycloak-operator \
    -n "$CAMUNDA_NAMESPACE"

echo ""
echo "============================================="
echo "Keycloak operator deployed successfully!"
echo "============================================="

# Verify installation
echo ""
echo "Verifying installation..."
kubectl get pods -n "$CAMUNDA_NAMESPACE" -l app.kubernetes.io/name=keycloak-operator

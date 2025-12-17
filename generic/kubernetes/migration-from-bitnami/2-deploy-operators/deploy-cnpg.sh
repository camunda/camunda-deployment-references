#!/bin/bash

# =============================================================================
# Deploy CloudNativePG Operator
# =============================================================================
# Deploys the CloudNativePG operator for PostgreSQL management
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../0-set-environment.sh" 2>/dev/null || true

echo "============================================="
echo "Deploying CloudNativePG Operator"
echo "============================================="
echo ""
echo "Version: ${CNPG_VERSION}"
echo "Namespace: ${CNPG_OPERATOR_NAMESPACE}"
echo ""

# Create operator namespace if needed
kubectl create namespace "$CNPG_OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install CloudNativePG operator CRDs and operator
echo "Installing CloudNativePG ${CNPG_VERSION}..."
kubectl apply -n "$CNPG_OPERATOR_NAMESPACE" --server-side -f \
    "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-${CNPG_VERSION}.yaml"

# Wait for operator to be ready
echo ""
echo "Waiting for operator to be ready..."
kubectl rollout status deployment \
    -n "$CNPG_OPERATOR_NAMESPACE" cnpg-controller-manager \
    --timeout=300s

echo ""
echo "============================================="
echo "CloudNativePG operator deployed successfully!"
echo "============================================="

# Verify installation
echo ""
echo "Verifying installation..."
kubectl get pods -n "$CNPG_OPERATOR_NAMESPACE" -l app.kubernetes.io/name=cloudnative-pg

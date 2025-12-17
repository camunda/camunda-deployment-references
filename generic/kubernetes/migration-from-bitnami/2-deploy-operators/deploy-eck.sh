#!/bin/bash

# =============================================================================
# Deploy ECK Operator
# =============================================================================
# Deploys the Elastic Cloud on Kubernetes (ECK) operator
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../0-set-environment.sh" 2>/dev/null || true

echo "============================================="
echo "Deploying ECK Operator"
echo "============================================="
echo ""
echo "Version: ${ECK_VERSION}"
echo "Namespace: ${ECK_OPERATOR_NAMESPACE}"
echo ""

# Install ECK operator CRDs
echo "Installing ECK CRDs..."
kubectl apply --server-side -f \
    "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"

# Create operator namespace if needed
kubectl create namespace "$ECK_OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install ECK operator
echo ""
echo "Installing ECK operator..."
kubectl apply -n "$ECK_OPERATOR_NAMESPACE" --server-side -f \
    "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"

# Wait for operator to be ready
echo ""
echo "Waiting for operator to be ready..."
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
    --timeout=300s \
    statefulset/elastic-operator \
    -n "$ECK_OPERATOR_NAMESPACE"

echo ""
echo "============================================="
echo "ECK operator deployed successfully!"
echo "============================================="

# Verify installation
echo ""
echo "Verifying installation..."
kubectl get pods -n "$ECK_OPERATOR_NAMESPACE"

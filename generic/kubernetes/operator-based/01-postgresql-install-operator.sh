#!/bin/bash
set -euo pipefail

# Script to install CloudNativePG operator for PostgreSQL
# Usage: ./01-postgresql-install-operator.sh [operator-namespace]

OPERATOR_NAMESPACE=${1:-cnpg-system}

echo "Installing CloudNativePG operator in namespace: $OPERATOR_NAMESPACE"

# Create namespace for the operator
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install the operator
# TODO(renovate): manage CNPG manifest version via Renovate (auto-bump)
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
  "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml"

echo "Waiting for operator to be ready..."
kubectl rollout status deployment \
  -n "$OPERATOR_NAMESPACE" cnpg-controller-manager

echo "CloudNativePG operator installed successfully!"

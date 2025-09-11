#!/bin/bash
set -euo pipefail

# Script to install CloudNativePG operator for PostgreSQL on OpenShift
# Usage: ./01-postgresql-install-operator.sh [operator-namespace]

OPERATOR_NAMESPACE=${1:-cnpg-system}

echo "Installing CloudNativePG operator in namespace: $OPERATOR_NAMESPACE"

# Create namespace for the operator
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Check if we're running on OpenShift
if kubectl api-resources | grep -q "securitycontextconstraints"; then
    echo "OpenShift detected - configuring Security Context Constraints..."

    # Create a service account for the operator if it doesn't exist
    kubectl create serviceaccount cnpg-controller-manager -n "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Grant the restricted-v2 SCC to the service account (OpenShift 4.11+)
    # This allows the operator to work with restricted security contexts
    if oc get scc restricted-v2 &>/dev/null; then
        oc adm policy add-scc-to-user restricted-v2 -z cnpg-controller-manager -n "$OPERATOR_NAMESPACE"
    else
        # Fallback for older OpenShift versions
        oc adm policy add-scc-to-user restricted -z cnpg-controller-manager -n "$OPERATOR_NAMESPACE"
    fi

    echo "SCC configured for CloudNativePG operator"
fi

# Install the operator
# TODO(renovate): manage CNPG manifest version via Renovate (auto-bump)
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
  "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml"

echo "Waiting for operator to be ready..."
kubectl rollout status deployment \
  -n "$OPERATOR_NAMESPACE" cnpg-controller-manager

echo "CloudNativePG operator installed successfully!"

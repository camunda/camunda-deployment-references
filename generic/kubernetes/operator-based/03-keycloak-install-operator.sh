#!/bin/bash
set -euo pipefail

# Script to install Keycloak Operator
# Usage: ./03-keycloak-install-operator.sh [operator-namespace]

OPERATOR_NAMESPACE=${1:-camunda}

echo "Installing Keycloak operator in namespace: $OPERATOR_NAMESPACE"

# Install CRDs
# TODO(renovate): manage keycloak manifest version via Renovate (auto-bump)
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml

kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml

echo "Waiting for CRDs to be established..."
sleep 10

# Create namespace if it doesn't exist
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install the operator
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/kubernetes.yml

echo "Waiting for operator to be ready..."
kubectl rollout status deployment \
  -n "$OPERATOR_NAMESPACE" keycloak-operator

echo "Keycloak operator installed successfully!"

#!/bin/bash
set -euo pipefail

# Script to install Keycloak Operator
# Installs CRDs and operator in the specified namespace

NAMESPACE=${1:-camunda}

echo "Installing Keycloak operator in namespace: $NAMESPACE"

# Install CRDs
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml

kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml

echo "Waiting for CRDs to be established..."
sleep 10

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install the operator
kubectl apply -n "$NAMESPACE" --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/kubernetes.yml

echo "Waiting for operator to be ready..."
kubectl rollout status deployment \
  -n "$NAMESPACE" keycloak-operator

echo "Keycloak operator installed successfully!"

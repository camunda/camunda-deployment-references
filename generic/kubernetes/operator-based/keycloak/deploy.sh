#!/bin/bash
# keycloak/deploy.sh - Deploy Keycloak via Keycloak operator (requires PostgresSQL)

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
KEYCLOAK_CONFIG_FILE=${KEYCLOAK_CONFIG_FILE:-"keycloak-instance-no-domain.yml"}

# renovate: datasource=github-releases depName=keycloak/keycloak
KEYCLOAK_VERSION="26.3.3"

# Install Keycloak operator CRDs
kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/keycloaks.k8s.keycloak.org-v1.yml"
kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml"


# Install Keycloak operator
kubectl apply -n "$CAMUNDA_NAMESPACE" --server-side -f \
  "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/kubernetes.yml"


# Wait for operator to be ready
kubectl wait --for=condition=available --timeout=300s deployment/keycloak-operator -n "$CAMUNDA_NAMESPACE"
echo "Keycloak operator deployed in namespace: $CAMUNDA_NAMESPACE"

# Deploy Keycloak

# Deploy Keycloak with variable substitution via envsubst
envsubst < "$KEYCLOAK_CONFIG_FILE" | kubectl apply -f - -n "$CAMUNDA_NAMESPACE"

# Wait for Keycloak instance to be ready
kubectl wait --for=condition=Ready --timeout=600s keycloak --all -n "$CAMUNDA_NAMESPACE"

echo "Keycloak deployment completed in namespace: $CAMUNDA_NAMESPACE"

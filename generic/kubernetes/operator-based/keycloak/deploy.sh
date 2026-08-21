#!/bin/bash
# keycloak/deploy.sh - Deploy Keycloak via Keycloak operator (requires PostgresSQL)

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
KEYCLOAK_CONFIG_FILE=${KEYCLOAK_CONFIG_FILE:-"keycloak-instance-no-domain.yml"}

# This version pins the Keycloak operator manifests fetched below. The operator and the
# server it manages are released together and are expected to match, so it tracks the
# Keycloak image Camunda distributes -- the one the Keycloak CRs in this directory run --
# rather than keycloak/keycloak-k8s-resources on its own, which would let the operator
# drift ahead of the server.
#
# camunda/keycloak tags carry a `quay-optimized-` prefix that the URLs below must not, so
# extractVersion strips it: Renovate compares `quay-optimized-26.6.4` with the bare version
# here and writes back the bare form. Rebuild and dated variants
# (`quay-optimized-26.6.4-1`, `quay-optimized-26.7.1-2026-08-14-001`) are left out, since
# keycloak-k8s-resources publishes no manifests under those -- the same set the CRs accept,
# so the two always resolve to one version. `.github/renovate.json5` on main, which
# Renovate reads for every base branch, groups them into one pull request so they also land
# together.
# renovate: datasource=docker depName=camunda/keycloak extractVersion=^quay-optimized-(?<version>\d+\.\d+\.\d+)$
KEYCLOAK_VERSION="26.6.4"

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

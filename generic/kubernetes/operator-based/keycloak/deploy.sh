#!/bin/bash
# keycloak/deploy.sh - Deploy Keycloak via Keycloak operator (requires PostgresSQL)

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
KEYCLOAK_CONFIG_FILE=${KEYCLOAK_CONFIG_FILE:-"keycloak-instance-no-domain.yml"}

# Version of the Keycloak operator and CRDs fetched below. It tracks the Keycloak that
# Camunda distributes -- the same image the Keycloak CRs in this directory pin -- so the
# operator and the instance it manages never drift apart; the manifests themselves are
# published upstream under the matching tag.
#
# The camunda/keycloak tags carry a `quay-optimized-` prefix that these URLs must not, so
# extractVersion strips it: Renovate compares `quay-optimized-26.6.4` with the bare version
# here and writes back the bare form. Dated and rebuild variants
# (`quay-optimized-26.6.4-1`, `quay-optimized-26.7.1-2026-08-14-001`) are left out on
# purpose, since upstream publishes no manifests under those -- the same set the CRs accept,
# so the two always resolve to one version. `.github/renovate.json5` on main, which Renovate
# reads for every base branch, groups them into one pull request so they also land together.
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

# Deploy Keycloak with variable substitution via envsubst (requires gettext)
if ! command -v envsubst >/dev/null 2>&1; then
  echo "Error: 'envsubst' command not found. Please install 'gettext' (which provides envsubst) and ensure it is on your PATH." >&2
  exit 1
fi
envsubst < "$KEYCLOAK_CONFIG_FILE" | kubectl apply -f - -n "$CAMUNDA_NAMESPACE"

# Wait for Keycloak instance to be ready
kubectl wait --for=condition=Ready --timeout=600s keycloak --all -n "$CAMUNDA_NAMESPACE"

echo "Keycloak deployment completed in namespace: $CAMUNDA_NAMESPACE"

#!/bin/bash
set -euo pipefail

# renovate: datasource=helm depName=camunda-platform versioning=regex:^13(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="13.10.2"

# Deploy Camunda Platform (domain mode with TLS)
# Run from: local/kubernetes/kind-single-region/

echo "Installing Camunda Platform (domain mode)..."

helm upgrade --install "camunda" camunda-platform \
    --repo https://helm.camunda.io \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values helm-values/values-domain.yml \
    --values helm-values/values-mkcert.yml

# Wait for the public Keycloak issuer to converge, then restart the app pods so
# they recover from the first-start crash-loop instead of waiting out the backoff.
# Reuses the shared readiness script (also shipped to customers and used by CI).
../../../generic/kubernetes/single-region/procedure/wait-for-keycloak.sh

echo ""
echo "Camunda Platform deployed"
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access: https://camunda.example.com"

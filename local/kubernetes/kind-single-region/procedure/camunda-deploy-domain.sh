#!/bin/bash
set -euo pipefail

# renovate: datasource=helm depName=camunda-platform versioning=regex:^13(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="13.5.2"

# Deploy Camunda Platform (domain mode with TLS)
# Run from: local/kubernetes/kind-single-region/

echo "Installing Camunda Platform (domain mode)..."

helm upgrade --install "camunda" camunda-platform \
    --repo https://helm.camunda.io \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values helm-values/values-domain.yml \
    --values helm-values/values-mkcert.yml

echo ""
echo "Camunda Platform deployed"
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access: https://camunda.example.com"

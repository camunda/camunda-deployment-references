#!/bin/bash
set -euo pipefail

# Deploy Camunda Platform (no-domain mode with port-forward)
# Run from: local/kubernetes/kind-single-region/

# renovate: datasource=helm depName=camunda-platform versioning=regex:^13(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="13.4.1"

echo "Installing Camunda Platform (no-domain mode)..."

helm upgrade --install "camunda" camunda-platform \
    --repo https://helm.camunda.io \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values helm-values/values-no-domain.yml

echo ""
echo "Camunda Platform deployed"
echo "Monitor: kubectl get pods -n camunda -w"

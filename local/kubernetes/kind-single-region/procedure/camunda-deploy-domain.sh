#!/bin/bash
set -euo pipefail

# renovate: datasource=helm depName=camunda-platform versioning=regex:^12(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="0.0.0-snapshot-alpha"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

# Deploy Camunda Platform (domain mode with TLS)
# Run from: local/kubernetes/kind-single-region/

echo "Installing Camunda Platform (domain mode)..."

helm upgrade --install "camunda" oci://ghcr.io/camunda/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values helm-values/values-domain.yml \
    --values helm-values/values-mkcert.yml

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install "camunda" camunda-platform \
#     --repo https://helm.camunda.io \
#     --version "$CAMUNDA_HELM_CHART_VERSION" \
#     --namespace "camunda" \
#     --values helm-values/values-domain.yml \
#     --values helm-values/values-mkcert.yml

echo ""
echo "Camunda Platform deployed!"
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access: https://camunda.example.com"

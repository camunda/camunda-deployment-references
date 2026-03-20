#!/bin/bash
set -euo pipefail

# Deploy Contour ingress controller
# Ref: https://projectcontour.io/docs/1.31/guides/kind/

# renovate: datasource=helm depName=contour registryUrl=https://projectcontour.github.io/helm-charts
CONTOUR_HELM_CHART_VERSION="20.3.0"

echo "Installing Contour ingress controller..."

# Add Contour Helm repository
helm repo add contour https://projectcontour.github.io/helm-charts/ 2>/dev/null || true
helm repo update contour

# Install Contour with Kind-specific settings
helm upgrade --install contour contour/contour \
    --version "$CONTOUR_HELM_CHART_VERSION" \
    --namespace projectcontour \
    --create-namespace \
    --set envoy.hostNetwork=true \
    --set envoy.service.type=NodePort \
    --set contour.ingressClass.default=true

echo "Waiting for Contour to be ready..."
kubectl wait --namespace projectcontour \
    --for=condition=available deployment/contour \
    --timeout=120s

echo "Waiting for Envoy to be ready..."
kubectl wait --namespace projectcontour \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=envoy \
    --timeout=120s

echo "Contour deployed successfully"

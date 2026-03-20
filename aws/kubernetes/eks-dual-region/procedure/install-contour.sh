#!/bin/bash
set -euo pipefail

# Deploy Contour ingress controller for EKS dual-region
# Contour is a modern, high-performance ingress controller based on Envoy proxy
# Replaces ingress-nginx as part of the migration effort

# renovate: datasource=helm depName=contour registryUrl=https://charts.bitnami.com/bitnami
CONTOUR_HELM_CHART_VERSION="20.3.0"

echo "Installing Contour ingress controller..."

helm upgrade --install contour contour \
    --repo https://charts.bitnami.com/bitnami \
    --version "$CONTOUR_HELM_CHART_VERSION" \
    --namespace projectcontour \
    --create-namespace \
    --set 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-backend-protocol=tcp' \
    --set 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-cross-zone-load-balancing-enabled=true' \
    --set 'envoy.service.annotations.service\.beta\.kubernetes\.io\/aws-load-balancer-type=nlb' \
    --set contour.ingressClass.create=true \
    --set contour.ingressClass.default=true \
    --set contour.ingressClass.name=contour

echo "Waiting for Contour controller to be ready..."
kubectl wait --namespace projectcontour \
    --for=condition=available deployment/contour-contour \
    --timeout=120s

echo "Waiting for Envoy proxy to be ready..."
kubectl wait --namespace projectcontour \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=envoy \
    --timeout=120s

echo "Contour ingress controller deployed successfully"

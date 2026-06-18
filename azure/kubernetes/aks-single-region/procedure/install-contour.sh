#!/bin/bash
set -euo pipefail

# Install Contour ingress controller on AKS with Azure Standard Load Balancer.
# Replaces ingress-nginx. Contour becomes the default IngressClass.

# renovate: datasource=helm depName=contour registryUrl=https://projectcontour.github.io/helm-charts
CONTOUR_HELM_CHART_VERSION="${CONTOUR_HELM_CHART_VERSION:-0.6.0}"

echo "Installing Contour ingress controller (chart ${CONTOUR_HELM_CHART_VERSION})..."

helm upgrade --install contour contour \
    --repo https://projectcontour.github.io/helm-charts/ \
    --version "$CONTOUR_HELM_CHART_VERSION" \
    --namespace projectcontour \
    --create-namespace \
    --set contour.ingressClass.default=true \
    --set envoy.kind=deployment \
    --set envoy.replicaCount=2 \
    --set envoy.service.type=LoadBalancer \
    --set envoy.service.externalTrafficPolicy=Local \
    --set "envoy.service.annotations.service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path=/healthz"

echo "Waiting for Envoy deployment to be available..."
kubectl wait deployment/contour-envoy \
    --namespace projectcontour \
    --for=condition=available \
    --timeout=300s

echo "Waiting for Envoy LoadBalancer IP..."
until kubectl get svc contour-envoy -n projectcontour \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null | grep -qE '^[0-9]+\.[0-9]+'; do
    echo "  waiting for LB IP..."
    sleep 10
done

LB_IP=$(kubectl get svc contour-envoy -n projectcontour \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Contour LB IP: ${LB_IP}"
echo "Contour deployed successfully."

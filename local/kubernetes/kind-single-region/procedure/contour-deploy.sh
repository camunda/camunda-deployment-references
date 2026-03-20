#!/bin/bash
set -euo pipefail

# Deploy Contour ingress controller for Kind

# renovate: datasource=helm depName=contour registryUrl=https://charts.bitnami.com/bitnami
CONTOUR_HELM_CHART_VERSION="21.1.4"

echo "Installing Contour ingress controller..."

helm upgrade --install contour contour \
    --repo https://charts.bitnami.com/bitnami \
    --version "$CONTOUR_HELM_CHART_VERSION" \
    --namespace projectcontour \
    --create-namespace \
    --set contour.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set contour.tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set contour.tolerations[0].operator="Exists" \
    --set contour.tolerations[0].effect="NoSchedule" \
    --set envoy.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set envoy.tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set envoy.tolerations[0].operator="Exists" \
    --set envoy.tolerations[0].effect="NoSchedule" \
    --set contour.ingressClass.default=true \
    --set envoy.replicaCount=1 \
    --set envoy.hostNetwork=true \
    --set envoy.service.type=NodePort

echo "Waiting for Contour and Envoy to be ready..."
kubectl wait --namespace projectcontour \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=contour \
    --timeout=120s

kubectl wait --namespace projectcontour \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=envoy \
    --timeout=120s

echo "Contour deployed successfully"

#!/bin/bash
set -euo pipefail

# Deploy Contour ingress controller with Envoy

# renovate: datasource=helm depName=contour registryUrl=https://projectcontour.github.io/helm-charts
CONTOUR_HELM_CHART_VERSION="0.4.0"

echo "Installing Contour ingress controller..."

helm upgrade --install contour contour \
    --repo https://projectcontour.github.io/helm-charts/ \
    --version "$CONTOUR_HELM_CHART_VERSION" \
    --namespace projectcontour \
    --create-namespace \
    --set envoy.kind=deployment \
    --set envoy.replicaCount=1 \
    --set envoy.hostNetwork=true \
    --set envoy.dnsPolicy=ClusterFirstWithHostNet \
    --set envoy.updateStrategy.type=Recreate \
    --set envoy.containerPorts.http=80 \
    --set envoy.containerPorts.https=443 \
    --set envoy.service.type=NodePort \
    --set envoy.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set envoy.tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set envoy.tolerations[0].operator="Exists" \
    --set envoy.tolerations[0].effect="NoSchedule" \
    --set contour.ingressClass.default=true

echo "Waiting for Envoy to be ready..."
kubectl wait --namespace projectcontour \
    --for=condition=available \
    --timeout=120s \
    deployment/contour-envoy

echo "Contour deployed successfully"

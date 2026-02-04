#!/bin/bash
set -euo pipefail

# Deploy Ingress NGINX controller

# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_HELM_CHART_VERSION="4.14.3"

echo "Installing Ingress NGINX controller..."

helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --version "$INGRESS_HELM_CHART_VERSION" \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set controller.tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set controller.tolerations[0].operator="Exists" \
    --set controller.tolerations[0].effect="NoSchedule" \
    --set controller.ingressClassResource.default=true \
    --set controller.replicaCount=1 \
    --set controller.admissionWebhooks.enabled=false \
    --set controller.hostNetwork=true \
    --set controller.service.type=NodePort

echo "Waiting for Ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s

echo "Ingress NGINX deployed successfully"

#!/bin/bash
set -euo pipefail

# Deploy Camunda Platform (domain mode with TLS)
# Run from: local/kubernetes/kind-single-region/

echo "Installing Camunda Platform (domain mode)..."

helm repo add camunda https://helm.camunda.io
helm repo update camunda

helm upgrade --install camunda camunda/camunda-platform \
    --namespace camunda \
    --values helm-values/values-domain.yml \
    --values helm-values/values-mkcert.yml

echo ""
echo "Camunda Platform deployed!"
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access: https://camunda.example.com"

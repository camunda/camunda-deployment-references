#!/bin/bash
set -euo pipefail

# Deploy Camunda Platform (no-domain mode with port-forward)
# Run from: local/kubernetes/kind-single-region/

echo "Installing Camunda Platform (no-domain mode)..."

helm repo add camunda https://helm.camunda.io
helm repo update camunda

helm upgrade --install camunda camunda/camunda-platform \
    --namespace camunda \
    --values helm-values/values-no-domain.yml

echo ""
echo "Camunda Platform deployed!"
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access via port-forward:"
echo "  kubectl port-forward svc/camunda-keycloak 18080:80 -n camunda"
echo "  kubectl port-forward svc/camunda-operate 8081:80 -n camunda"
echo "  kubectl port-forward svc/camunda-tasklist 8082:80 -n camunda"

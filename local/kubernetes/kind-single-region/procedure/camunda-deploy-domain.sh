#!/bin/bash
set -euo pipefail

# renovate: datasource=helm depName=camunda-platform versioning=regex:^13(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="13.10.2"

# Deploy Camunda Platform (domain mode with TLS)
# Run from: local/kubernetes/kind-single-region/

echo "Installing Camunda Platform (domain mode)..."

helm upgrade --install "camunda" camunda-platform \
    --repo https://helm.camunda.io \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values helm-values/values-domain.yml \
    --values helm-values/values-mkcert.yml

# Wait (bounded, fail-open) for the public Keycloak issuer, then restart the app
# pods so they recover from the first-start crash-loop instead of waiting out the
# backoff. On timeout it warns and continues. Reuses the shared readiness script
# (also shipped to customers and used by CI). Under CI the host may not trust the
# mkcert CA (mkcert -install is best-effort), so skip TLS verification there only;
# local runs keep it enabled.
insecure_flag=""
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    insecure_flag="true"
fi
KEYCLOAK_WAIT_INSECURE="$insecure_flag" \
    ../../../generic/kubernetes/single-region/procedure/wait-for-keycloak.sh

echo ""
echo "Camunda Platform deployed"
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access: https://camunda.example.com"

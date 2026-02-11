#!/bin/bash
set -euo pipefail

# renovate: datasource=helm depName=camunda-platform versioning=regex:^12(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="0.0.0-snapshot-alpha"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

# Deploy Camunda Platform (domain mode with TLS)
# Run from: local/kubernetes/kind-single-region/
# Layers operator-based values from generic/kubernetes/operator-based/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_VALUES_DIR="$SCRIPT_DIR/../../../../generic/kubernetes/operator-based"
export CAMUNDA_DOMAIN="camunda.example.com"

echo "Installing Camunda Platform (domain mode)..."

helm upgrade --install "camunda" oci://ghcr.io/camunda/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
    --values <(envsubst < "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-domain-values.yml") \
    --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
    --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
    --values helm-values/values-domain.yml \
    --values helm-values/values-mkcert.yml

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install "camunda" camunda-platform \
#     --repo https://helm.camunda.io \
#     --version "$CAMUNDA_HELM_CHART_VERSION" \
#     --namespace "camunda" \
#     --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
#     --values <(envsubst < "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-domain-values.yml") \
#     --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
#     --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
#     --values helm-values/values-domain.yml \
#     --values helm-values/values-mkcert.yml

echo ""
echo "Camunda Platform deployed"
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access: https://camunda.example.com"

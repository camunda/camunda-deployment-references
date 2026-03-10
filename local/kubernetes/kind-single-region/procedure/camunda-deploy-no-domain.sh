#!/bin/bash
set -euo pipefail

# Deploy Camunda Platform (no-domain mode with port-forward)
# Run from: local/kubernetes/kind-single-region/
# Layers operator-based values from generic/kubernetes/operator-based/

# renovate: datasource=helm depName=camunda-platform versioning=regex:^14(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://registry.camunda.cloud
export CAMUNDA_HELM_CHART_VERSION="14-dev-latest"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_VALUES_DIR="$SCRIPT_DIR/../../../../generic/kubernetes/operator-based"

echo "Installing Camunda Platform (no-domain mode)..."

helm upgrade --install "camunda" oci://registry.camunda.cloud/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
    --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
    --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
    --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
    --values helm-values/values-no-domain.yml

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install "camunda" camunda-platform \
#     --repo https://helm.camunda.io \
#     --version "$CAMUNDA_HELM_CHART_VERSION" \
#     --namespace "camunda" \
#     --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
#     --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
#     --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
#     --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
#     --values helm-values/values-no-domain.yml



echo ""
echo "Camunda Platform deployed"
echo "Monitor: kubectl get pods -n camunda -w"

#!/bin/bash
set -euo pipefail

# Deploy Camunda Platform (PG-only, no-domain mode with port-forward)
# Uses PostgreSQL (RDBMS) for secondary storage instead of Elasticsearch.
# Optimize is disabled in this mode.
# Run from: local/kubernetes/kind-single-region/
# Layers operator-based values from generic/kubernetes/operator-based/

# renovate: datasource=helm depName=camunda-platform versioning=regex:^14(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="14-dev-latest"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_VALUES_DIR="$SCRIPT_DIR/../../../../generic/kubernetes/operator-based"

echo "Installing Camunda Platform (PG-only, no-domain mode)..."

helm upgrade --install "camunda" oci://registry.camunda.cloud/team-distribution/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "camunda" \
    --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
    --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
    --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
    --values helm-values/values-no-domain.yml \
    --values "$OPERATOR_VALUES_DIR/postgresql/camunda-rdbms-values.yml"

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install "camunda" camunda-platform \
#     --repo https://helm.camunda.io \
#     --version "$CAMUNDA_HELM_CHART_VERSION" \
#     --namespace "camunda" \
#     --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
#     --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
#     --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
#     --values helm-values/values-no-domain.yml \
#     --values "$OPERATOR_VALUES_DIR/postgresql/camunda-rdbms-values.yml"

echo ""
echo "Camunda Platform deployed (PG-only mode — Optimize disabled)"
echo "Monitor: kubectl get pods -n camunda -w"

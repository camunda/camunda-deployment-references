#!/bin/bash
set -euo pipefail

# Deploy Camunda Platform (domain mode with TLS)
# Run from: local/kubernetes/kind-single-region/
# Layers operator-based values from generic/kubernetes/operator-based/
#
# Environment variables:
#   SECONDARY_STORAGE: "elasticsearch" (default) or "postgres"
#                      Controls the secondary storage backend.
#                      - elasticsearch: Uses Elasticsearch (full platform with Optimize)
#                      - postgres: Uses PostgreSQL RDBMS only (Optimize disabled)

# renovate: datasource=helm depName=camunda-platform versioning=regex:^14(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="14-dev-latest"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_VALUES_DIR="$SCRIPT_DIR/../../../../generic/kubernetes/operator-based"
export CAMUNDA_DOMAIN="camunda.example.com"

# Validate SECONDARY_STORAGE is set
if [[ -z "${SECONDARY_STORAGE:-}" ]]; then
    echo "ERROR: SECONDARY_STORAGE environment variable is required."
    echo "       Valid values: elasticsearch, postgres"
    exit 1
fi

if [[ "$SECONDARY_STORAGE" != "elasticsearch" && "$SECONDARY_STORAGE" != "postgres" ]]; then
    echo "ERROR: Invalid SECONDARY_STORAGE value: $SECONDARY_STORAGE"
    echo "       Valid values: elasticsearch, postgres"
    exit 1
fi

if [[ "$SECONDARY_STORAGE" == "elasticsearch" ]]; then
    echo "Installing Camunda Platform (domain mode, Elasticsearch)..."

    helm upgrade --install "camunda" oci://registry.camunda.cloud/team-distribution/camunda-platform \
        --version "$CAMUNDA_HELM_CHART_VERSION" \
        --namespace "camunda" \
        --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
        --values <(envsubst < "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-domain-values.yml") \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
        --values helm-values/values-domain.yml \
        --values helm-values/values-mkcert.yml
else
    echo "Installing Camunda Platform (domain mode, PostgreSQL RDBMS)..."

    helm upgrade --install "camunda" oci://registry.camunda.cloud/team-distribution/camunda-platform \
        --version "$CAMUNDA_HELM_CHART_VERSION" \
        --namespace "camunda" \
        --values <(envsubst < "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-domain-values.yml") \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
        --values helm-values/values-domain.yml \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-rdbms-values.yml" \
        --values helm-values/values-mkcert.yml
fi

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# if [[ "$SECONDARY_STORAGE" == "elasticsearch" ]]; then
#     helm upgrade --install "camunda" camunda-platform \
#         --repo https://helm.camunda.io \
#         --version "$CAMUNDA_HELM_CHART_VERSION" \
#         --namespace "camunda" \
#         --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
#         --values <(envsubst < "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-domain-values.yml") \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
#         --values helm-values/values-domain.yml \
#         --values helm-values/values-mkcert.yml
# else
#     helm upgrade --install "camunda" camunda-platform \
#         --repo https://helm.camunda.io \
#         --version "$CAMUNDA_HELM_CHART_VERSION" \
#         --namespace "camunda" \
#         --values <(envsubst < "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-domain-values.yml") \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
#         --values helm-values/values-domain.yml \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-rdbms-values.yml" \
#         --values helm-values/values-mkcert.yml
# fi

echo ""
if [[ "$SECONDARY_STORAGE" == "postgres" ]]; then
    echo "Camunda Platform deployed (PostgreSQL RDBMS — Optimize disabled)"
else
    echo "Camunda Platform deployed (Elasticsearch)"
fi
echo "Monitor: kubectl get pods -n camunda -w"
echo ""
echo "Access: https://camunda.example.com"

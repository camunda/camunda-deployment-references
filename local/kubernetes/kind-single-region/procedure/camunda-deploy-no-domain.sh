#!/bin/bash
set -euo pipefail

# Deploy Camunda Platform (no-domain mode with port-forward)
# Run from: local/kubernetes/kind-single-region/
# Layers operator-based values from generic/kubernetes/operator-based/
#
# Environment variables:
#   SECONDARY_STORAGE: "elasticsearch" or "postgres" (required, no default)
#                      Controls the secondary storage backend.
#                      - elasticsearch: Uses Elasticsearch (full platform with Optimize)
#                      - postgres: Uses PostgreSQL RDBMS only (Optimize disabled)

# Camunda Helm chart version.
#
# Pre-release: the chart for this Camunda minor is not published to a public Helm
# repo yet, and the dev build lives only in an internal OCI registry that needs
# authentication. So the active install below builds the chart from source (git
# clone), which needs no registry login. This pinned version is still consumed by
# the standard-Helm install in the [release-duty] block below and by CI checks.
# renovate: datasource=helm depName=camunda-platform versioning=regex:^15(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="15-dev-latest"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_VALUES_DIR="$SCRIPT_DIR/../../../../generic/kubernetes/operator-based"

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

# Build the Camunda chart from source so this guide needs no registry
# authentication during the pre-release phase (sets LOCAL_CHART).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=build-camunda-chart.sh
source "$SCRIPT_DIR/build-camunda-chart.sh"

if [[ "$SECONDARY_STORAGE" == "elasticsearch" ]]; then
    echo "Installing Camunda Platform (no-domain mode, Elasticsearch)..."

    helm upgrade --install "camunda" "$LOCAL_CHART" \
        --namespace "camunda" \
        --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
        --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
        --values helm-values/values-no-domain.yml
else
    echo "Installing Camunda Platform (no-domain mode, PostgreSQL RDBMS)..."

    helm upgrade --install "camunda" "$LOCAL_CHART" \
        --namespace "camunda" \
        --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
        --values helm-values/values-no-domain.yml \
        --values "$OPERATOR_VALUES_DIR/postgresql/camunda-rdbms-values.yml"
fi

# TODO: [release-duty] before the release, remove the source-build install above
# (the "source .../build-camunda-chart.sh" line and the "helm upgrade --install"
# calls using "$LOCAL_CHART") and uncomment the standard Helm install below.

# if [[ "$SECONDARY_STORAGE" == "elasticsearch" ]]; then
#     helm upgrade --install "camunda" camunda-platform \
#         --repo https://helm.camunda.io \
#         --version "$CAMUNDA_HELM_CHART_VERSION" \
#         --namespace "camunda" \
#         --values "$OPERATOR_VALUES_DIR/elasticsearch/camunda-elastic-values.yml" \
#         --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
#         --values helm-values/values-no-domain.yml
# else
#     helm upgrade --install "camunda" camunda-platform \
#         --repo https://helm.camunda.io \
#         --version "$CAMUNDA_HELM_CHART_VERSION" \
#         --namespace "camunda" \
#         --values "$OPERATOR_VALUES_DIR/keycloak/camunda-keycloak-no-domain-values.yml" \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-identity-values.yml" \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-webmodeler-values.yml" \
#         --values helm-values/values-no-domain.yml \
#         --values "$OPERATOR_VALUES_DIR/postgresql/camunda-rdbms-values.yml"
# fi

echo ""
if [[ "$SECONDARY_STORAGE" == "postgres" ]]; then
    echo "Camunda Platform deployed (PostgreSQL RDBMS — Optimize disabled)"
else
    echo "Camunda Platform deployed (Elasticsearch)"
fi
echo "Monitor: kubectl get pods -n camunda -w"

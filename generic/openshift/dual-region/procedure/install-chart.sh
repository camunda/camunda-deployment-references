#!/bin/bash
set -euo pipefail

helm repo add camunda https://helm.camunda.io
helm repo update

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" \
   oci://registry.camunda.cloud/team-distribution/camunda-platform \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_0" \
  --namespace "$CAMUNDA_NAMESPACE_0" \
  -f generated-values-region-0.yml

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" \
   oci://registry.camunda.cloud/team-distribution/camunda-platform \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_1" \
  --namespace "$CAMUNDA_NAMESPACE_1" \
  -f generated-values-region-1.yml

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install \
#    "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
#   --version "$HELM_CHART_VERSION" \
#   --kube-context "$CLUSTER_0" \
#   --namespace "$CAMUNDA_NAMESPACE_0" \
#   -f generated-values-region-0.yml

# helm upgrade --install \
#   "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
#   --version "$HELM_CHART_VERSION" \
#   --kube-context "$CLUSTER_1" \
#   --namespace "$CAMUNDA_NAMESPACE_1" \
#   -f generated-values-region-1.yml

#!/bin/bash
set -euo pipefail

helm repo add camunda https://helm.camunda.io
helm repo update

# Resolve the broker image of the chart being installed so the cross-region
# DNS-gate initContainer (see helm-values/values-base.yml) reuses the exact
# same image as the broker — already pulled on the node, no extra pull, and no
# hardcoded tag to maintain. The generated values carry a literal ${BROKER_IMAGE}
# placeholder (passed through the first envsubst via ${DOLLAR}); resolve it here.
BROKER_IMAGE="$(helm show values \
  oci://registry.camunda.cloud/team-distribution/camunda-platform \
  --version "$HELM_CHART_VERSION" \
  | yq -r '(.orchestration.image // .zeebe.image) | ([.registry, .repository] | map(. // "") | map(select(. != "")) | join("/")) + ":" + .tag')"
export BROKER_IMAGE
echo "Cross-region DNS-gate initContainer will reuse broker image: $BROKER_IMAGE"

for region_values in generated-values-region-0.yml generated-values-region-1.yml; do
  # Single quotes are envsubst's SHELL-FORMAT (only ${BROKER_IMAGE} is replaced),
  # not a shell expansion — leave everything else in the file untouched.
  # shellcheck disable=SC2016
  envsubst '${BROKER_IMAGE}' <"$region_values" >"$region_values.tmp"
  mv "$region_values.tmp" "$region_values"
done

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_0" \
  --namespace "$CAMUNDA_NAMESPACE_0" \
  -f generated-values-region-0.yml

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_1" \
  --namespace "$CAMUNDA_NAMESPACE_1" \
  -f generated-values-region-1.yml

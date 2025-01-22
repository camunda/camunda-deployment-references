#!/bin/bash

helm upgrade --install \
   "$HELM_RELEASE_NAME" camunda/camunda-platform \
  --repo https://helm.camunda.io \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_1_NAME" \
  --namespace "$CAMUNDA_NAMESPACE_1" \
  -f generated-values-region-1.yml

helm upgrade --install
  "$HELM_RELEASE_NAME" camunda/camunda-platform \
  --repo https://helm.camunda.io \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_2_NAME" \
  --namespace "$CAMUNDA_NAMESPACE_2" \
  -f generated-values-region-2.yml

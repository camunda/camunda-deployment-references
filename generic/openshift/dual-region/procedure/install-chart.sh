#!/bin/bash

helm repo add camunda https://helm.camunda.io
helm repo update

helm upgrade --install \
   "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_1_NAME" \
  --namespace "$CAMUNDA_NAMESPACE_1" \
  -f generated-values-region-1.yml

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_2_NAME" \
  --namespace "$CAMUNDA_NAMESPACE_2" \
  -f generated-values-region-2.yml

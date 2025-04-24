#!/bin/bash

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" camunda-platform \
  --repo https://helm.camunda.io \
  --version "$CAMUNDA_HELM_CHART_VERSION" \
  --namespace "$CAMUNDA_NAMESPACE" \
  -f generated-values.yml


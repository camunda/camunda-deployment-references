helm upgrade --install \
  camunda camunda-platform \
  --repo https://helm.camunda.io \
  --version "$CAMUNDA_HELM_CHART_VERSION" \
  --namespace camunda \
  -f generated-values.yml

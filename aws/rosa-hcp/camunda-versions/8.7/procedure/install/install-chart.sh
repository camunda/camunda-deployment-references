# helm upgrade --install \
#   camunda camunda-platform \
#   --repo https://helm.camunda.io \
#   --version "$CAMUNDA_HELM_CHART_VERSION" \
#   --namespace camunda \
#   -f generated-values.yml

# TODO: before the release, update this!

helm upgrade --install \
    camunda oci://ghcr.io/camunda/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" --namespace camunda \
    -f generated-values.yml

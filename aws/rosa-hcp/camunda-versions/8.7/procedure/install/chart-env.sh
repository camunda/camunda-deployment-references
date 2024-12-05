# The Camunda 8 Helm Chart version
# renovate: datasource=helm depName=camunda-platform versioning=regex:^12(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="0.0.0-snapshot-alpha"

# TODO: before the release, update this!
# TODO: fin a way to abstract the install command
# helm upgrade --install \                                                      1 (1.606s) < 21:00:15
          # camunda oci://ghcr.io/camunda/helm/camunda-platform  \
          # --version 0.0.0-snapshot-alpha --namespace camunda \
          # -f generated-values.yml

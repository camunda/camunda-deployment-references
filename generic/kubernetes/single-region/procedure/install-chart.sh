#!/bin/bash

# Warn that this deploys an unreleased, in-development chart (to stderr).
cat >&2 <<'PRERELEASE_WARNING'

  ############################################################################
  #  ⚠  PRE-RELEASE — NOT A STABLE CAMUNDA RELEASE                           #
  #                                                                          #
  #  This deploys an unreleased, in-development Camunda 8 chart.             #
  #  It may be unstable or fail to start — that is expected here.            #
  #                                                                          #
  #  Need a stable, supported setup? Follow the Administrator quickstart:    #
  #  https://docs.camunda.io/docs/self-managed/quickstart/administrator-quickstart/
  ############################################################################

PRERELEASE_WARNING

helm upgrade --install \
    "$CAMUNDA_RELEASE_NAME" oci://registry.camunda.cloud/team-distribution/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" --namespace "$CAMUNDA_NAMESPACE" \
    -f generated-values.yml

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install \
#   "$CAMUNDA_RELEASE_NAME" camunda-platform \
#   --repo https://helm.camunda.io \
#   --version "$CAMUNDA_HELM_CHART_VERSION" \
#   --namespace "$CAMUNDA_NAMESPACE" \
#   -f generated-values.yml

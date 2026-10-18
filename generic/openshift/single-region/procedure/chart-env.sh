#!/bin/bash

# The Camunda 8 Helm Chart version
# Retain this dev selector until the 8.11 registry chart is verified.
# renovate: datasource=helm depName=camunda-platform versioning=regex:^15(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io renovate-inert-ok
export CAMUNDA_HELM_CHART_VERSION="15-dev-latest"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

export CAMUNDA_NAMESPACE="camunda"
export CAMUNDA_RELEASE_NAME="camunda"

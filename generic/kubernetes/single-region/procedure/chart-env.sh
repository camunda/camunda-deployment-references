#!/bin/bash

# The Camunda 8 Helm Chart version
# Parked: retain the working chart until an 8.11 chart exists.
# renovate: datasource=helm depName=camunda-platform versioning=regex:^15(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io renovate-inert-ok
export CAMUNDA_HELM_CHART_VERSION="15-dev-latest"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

export CAMUNDA_NAMESPACE="camunda"
export CAMUNDA_RELEASE_NAME="camunda"

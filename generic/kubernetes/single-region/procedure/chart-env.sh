#!/bin/bash

# The Camunda 8 Helm Chart version
# renovate: datasource=helm depName=camunda-platform versioning=regex:^13(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="0.0.0-snapshot-alpha"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

export CAMUNDA_NAMESPACE="camunda"
export CAMUNDA_RELEASE_NAME="camunda"

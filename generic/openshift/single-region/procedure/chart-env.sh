#!/bin/bash

# The Camunda 8 Helm Chart version
# renovate: datasource=helm depName=camunda-platform versioning=regex:^13(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="13.0.0"

export CAMUNDA_NAMESPACE="camunda"
export CAMUNDA_RELEASE_NAME="camunda"

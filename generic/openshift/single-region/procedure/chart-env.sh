#!/bin/bash

# The Camunda 8 Helm Chart version
# renovate: datasource=helm depName=camunda-platform registryUrl=https://helm.camunda.io versioning=regex:^12(\.(?<minor>\d+))?(\.(?<patch>\d+))?$
export CAMUNDA_HELM_CHART_VERSION="12.7.3"

export CAMUNDA_NAMESPACE="camunda"
export CAMUNDA_RELEASE_NAME="camunda"

#!/bin/bash

# Source this file to set the required environment variables

# Camunda namespace
export CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"

# Camunda domain
export CAMUNDA_DOMAIN="${CAMUNDA_DOMAIN:-localhost}"

# The Camunda 8 Helm Chart version
# renovate: datasource=helm depName=camunda-platform versioning=regex:^12(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="0.0.0-snapshot-alpha"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version
export CAMUNDA_RELEASE_NAME="camunda"

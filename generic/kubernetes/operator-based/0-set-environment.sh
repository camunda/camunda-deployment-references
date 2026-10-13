#!/bin/bash

# Source this file to set the required environment variables

# Camunda namespace
export CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"

# Camunda domain
export CAMUNDA_DOMAIN="${CAMUNDA_DOMAIN:-localhost}"

# The Camunda 8 Helm Chart version
# Parked: retain the working chart until an 8.11 chart exists.
# renovate: datasource=helm depName=camunda-platform versioning=regex:^15(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io renovate-inert-ok
export CAMUNDA_HELM_CHART_VERSION="15-dev-latest"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version
export CAMUNDA_RELEASE_NAME="camunda"

#!/bin/bash

# Your standard region that you host AWS resources in
export REGION="$AWS_REGION"

# The Camunda 8 Helm Chart version
# renovate: datasource=helm depName=camunda-platform versioning=regex:^12(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export CAMUNDA_HELM_CHART_VERSION="0.0.0-snapshot-alpha"
# TODO: [release-duty] before the release, update this!

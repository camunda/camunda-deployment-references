#!/bin/bash

###############################################################################
# Important: Adjust the following environment variables to your setup         #
###############################################################################

# The script must be executed with
# . ./export_environment_prerequisites.sh
# to export the environment variables to the current shell

# The AWS regions of your OpenShift cluster 1 and 2
export CLUSTER_1_REGION="us-east-1"
export CLUSTER_2_REGION="us-east-2"

# The names of your OpenShift clusters in regions 1 and 2
export CLUSTER_1_NAME=""
export CLUSTER_2_NAME=""

# The OpenShift namespaces for each region where Camunda 8 should be running
# Namespace names must be unique to route the traffic
export CAMUNDA_NAMESPACE_1="camunda-$CLUSTER_1_NAME"
export CAMUNDA_NAMESPACE_2="camunda-$CLUSTER_2_NAME"

# The backup bucket access variables
export AWS_ACCESS_KEY_ES=""
export AWS_SECRET_ACCESS_KEY_ES=""
export AWS_ES_BUCKET_NAME=""
export AWS_ES_BUCKET_REGION=""

# The Helm release name used for installing Camunda 8 in both Kubernetes clusters
export CAMUNDA_RELEASE_NAME=camunda

# renovate: datasource=helm depName=camunda-platform versioning=regex:^13(\.(?<minor>\d+))?(\.(?<patch>\d+))?$ registryUrl=https://helm.camunda.io
export HELM_CHART_VERSION="0.0.0-snapshot-alpha"
# TODO: [release-duty] before the release, update this!
# TODO: [release-duty] adjust renovate comment to bump the major version

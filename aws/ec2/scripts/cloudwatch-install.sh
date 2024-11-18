#!/bin/bash
set -euo pipefail

# Executed on remote host, defaults should be set here or env vars preconfigured on remote host
USERNAME=${USERNAME:-"camunda"}
MNT_DIR=${MNT_DIR:-"/opt/camunda"}
# renovate: datasource=docker depName=amazon/cloudwatch-agent
CLOUDWATCH_VERSION="1.300049.1b929"

# Optional feature, disabled by default and can be overwritten with the env var "CLOUDWATCH_ENABLED"
# Install the CloudWatch agent on the EC2 instance and creates the necessary directories for the configuration files.

wget "https://amazoncloudwatch-agent.s3.amazonaws.com/debian/amd64/${CLOUDWATCH_VERSION}/amazon-cloudwatch-agent.deb"

sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

rm -rf amazon-cloudwatch-agent.deb

sudo -u "${USERNAME}" mkdir -p "${MNT_DIR}/cloudwatch"

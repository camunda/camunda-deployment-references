#!/bin/bash
set -euo pipefail

# Executed on remote host, defaults should be set here or env vars preconfigured on remote host
USERNAME=${USERNAME:-"camunda"}
MNT_DIR=${MNT_DIR:-"/opt/camunda"}
CLOUDWATCH_VERSION="1.300049.1b929"

ARCH=$(uname -m)
TARGET_ARCH="amd64"

if [ "$ARCH" = "x86_64" ]; then
    echo "The system is running on amd64 (x86_64)."
    TARGET_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    echo "The system is running on arm64 (aarch64)."
    TARGET_ARCH="arm64"
fi

# Optional feature, disabled by default and can be overwritten with the env var "CLOUDWATCH_ENABLED"
# Install the CloudWatch agent on the EC2 instance and creates the necessary directories for the configuration files.

wget "https://amazoncloudwatch-agent.s3.amazonaws.com/debian/${TARGET_ARCH}/${CLOUDWATCH_VERSION}/amazon-cloudwatch-agent.deb"

sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

rm -rf amazon-cloudwatch-agent.deb

sudo -u "${USERNAME}" mkdir -p "${MNT_DIR}/cloudwatch"

#!/bin/bash
set -euo pipefail

# Optional feature, disabled by default and can be overwrittne witht the env var "CLOUDWATCH_ENABLED"
# Install the CloudWatch agent on the EC2 instance and creates the necessary directories for the configuration files.

# TODO: update the CloudWatch agent version via Renovate
wget https://amazoncloudwatch-agent.s3.amazonaws.com/debian/amd64/1.300040.0b650/amazon-cloudwatch-agent.deb

sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

rm -rf amazon-cloudwatch-agent.deb

mkdir -p "${MNT_DIR}/cloudwatch"

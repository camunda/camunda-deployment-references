#!/bin/bash
set -euo pipefail

source ./helpers.sh

# Optional feature, disabled by default and can be overwrittne witht the env var "CLOUDWATCH_ENABLED"
# Copies the configuration files for the CloudWatch agent to the EC2 instance and starts the agent.

transfer_file ../configs/prometheus.yaml "${MNT_DIR}/cloudwatch/"
transfer_file ../configs/amazon-cloudwatch-agent.json "${MNT_DIR}/cloudwatch/"

remote_cmd "sudo amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:${MNT_DIR}/cloudwatch/amazon-cloudwatch-agent.json -s"

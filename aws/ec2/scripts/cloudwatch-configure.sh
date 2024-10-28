#!/bin/bash
set -euo pipefail

source "${CURRENT_DIR}/helpers.sh"

# Optional feature, disabled by default and can be overwritten with the env var "CLOUDWATCH_ENABLED"
# Copies the configuration files for the CloudWatch agent to the EC2 instance and starts the agent.

transfer_file "${CURRENT_DIR}/../configs/prometheus.yaml" "${MNT_DIR}/cloudwatch/" prometheus.yaml
transfer_file "${CURRENT_DIR}/../configs/amazon-cloudwatch-agent.json" "${MNT_DIR}/cloudwatch/" amazon-cloudwatch-agent.json

remote_cmd "sudo amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:${MNT_DIR}/cloudwatch/amazon-cloudwatch-agent.json -s"

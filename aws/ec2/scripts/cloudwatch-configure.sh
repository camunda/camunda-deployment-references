#!/bin/bash

# Optional feature, disabled by default and can be overwrittne witht the env var "CLOUDWATCH_ENABLED"
# Copies the configuration files for the CloudWatch agent to the EC2 instance and starts the agent.

scp -o "ProxyJump=admin@${BASTION_IP}" ../configs/prometheus.yaml "admin@${ip}:${MNT_DIR}/cloudwatch/"
scp -o "ProxyJump=admin@${BASTION_IP}" ../configs/amazon-cloudwatch-agent.json "admin@${ip}:${MNT_DIR}/cloudwatch/"

ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/camunda/cloudwatch/amazon-cloudwatch-agent.json -s'

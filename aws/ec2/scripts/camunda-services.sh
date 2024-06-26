#!/bin/bash

# Copies the final configuration files to the EC2 instance and starts the Camunda 8 services.

echo "Copying the configuration files to the remote server."
scp -o "ProxyJump=admin@${BASTION_IP}" camunda-environment.tmp "admin@${ip}:${MNT_DIR}/camunda/config/camunda-environment"
rm -rf camunda-environment.tmp

scp -o "ProxyJump=admin@${BASTION_IP}" ../configs/connectors-environment "admin@${ip}:${MNT_DIR}/connectors/"

echo "Installing the Camunda 8 systemd service on the remote server."
scp -o "ProxyJump=admin@${BASTION_IP}" ../configs/camunda.service "admin@${ip}:${MNT_DIR}"
scp -o "ProxyJump=admin@${BASTION_IP}" ../configs/connectors.service "admin@${ip}:${MNT_DIR}"


ssh -J "admin@${BASTION_IP}" "admin@${ip}" "sudo mv ${MNT_DIR}/camunda.service /etc/systemd/system/camunda.service"
ssh -J "admin@${BASTION_IP}" "admin@${ip}" "sudo mv ${MNT_DIR}/connectors.service /etc/systemd/system/connectors.service"
# Install and activate Camunda 8 Service
ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl daemon-reload'
ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl enable camunda.service'
ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl start camunda.service'
# restarting the service in case the script is called twice with config changes
ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl restart camunda.service'

# Install and activate Connectors Service
ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl enable connectors.service'
ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl start connectors.service'
# restarting the service in case the script is called twice with config changes
ssh -J "admin@${BASTION_IP}" "admin@${ip}" 'sudo systemctl restart connectors.service'

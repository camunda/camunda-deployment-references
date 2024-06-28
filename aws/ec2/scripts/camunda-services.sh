#!/bin/bash
set -euo pipefail

source ./helpers.sh

# Copies the final configuration files to the EC2 instance and starts the Camunda 8 services.

echo "Copying the configuration files to the remote server."
transfer_file camunda-environment.tmp "${MNT_DIR}/camunda/config/camunda-environment"
rm -rf camunda-environment.tmp

transfer_file ../configs/connectors-environment "${MNT_DIR}/connectors/"

echo "Installing the Camunda 8 systemd service on the remote server."
transfer_file ../configs/camunda.service "${MNT_DIR}"
transfer_file ../configs/connectors.service "${MNT_DIR}"

remote_cmd "sudo mv ${MNT_DIR}/camunda.service /etc/systemd/system/camunda.service"
remote_cmd "sudo mv ${MNT_DIR}/connectors.service /etc/systemd/system/connectors.service"

# Install and activate Camunda 8 Service
remote_cmd 'sudo systemctl daemon-reload'
remote_cmd 'sudo systemctl enable camunda.service --now'
# restarting the service in case the script is called twice with config changes
remote_cmd 'sudo systemctl restart camunda.service'

# Install and activate Connectors Service
remote_cmd 'sudo systemctl enable connectors.service --now'
# restarting the service in case the script is called twice with config changes
remote_cmd 'sudo systemctl restart connectors.service'

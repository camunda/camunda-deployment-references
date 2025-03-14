#!/bin/bash
set -euo pipefail

source "${CURRENT_DIR}/helpers.sh"

# Copies the final configuration files to the EC2 instance and starts the Camunda 8 services.

echo "[INFO] Copying the configuration files to the remote server."
transfer_file "${CURRENT_DIR}/camunda-environment.tmp" "${MNT_DIR}/camunda/config/camunda-environment" camunda-environment.tmp
rm -rf "${CURRENT_DIR}/camunda-environment.tmp"

transfer_file "${CURRENT_DIR}/connectors-environment.tmp" "${MNT_DIR}/connectors/connectors-environment" connectors-environment.tmp
rm -rf "${CURRENT_DIR}/connectors-environment.tmp"

echo "[INFO] Installing the Camunda 8 systemd service on the remote server."
transfer_file "${CURRENT_DIR}/../configs/camunda.service" "${MNT_DIR}" camunda.service
transfer_file "${CURRENT_DIR}/../configs/connectors.service" "${MNT_DIR}" connectors.service

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

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../configs"
MNT_DIR="${MNT_DIR:-"/opt/camunda"}"

source "${SCRIPT_DIR}/helpers.sh"

# Copies the final configuration files to the remote instance and starts the Camunda 8 services.

echo "[INFO] Copying the configuration files to the remote server."
transfer_file "${SCRIPT_DIR}/camunda-environment.tmp" "${MNT_DIR}/camunda/config/camunda-environment" camunda-environment.tmp
rm -rf "${SCRIPT_DIR}/camunda-environment.tmp"

transfer_file "${CURRENT_DIR}/connectors-environment.tmp" "${MNT_DIR}/connectors/connectors-environment" connectors-environment.tmp
rm -rf "${SCRIPT_DIR}/connectors-environment.tmp"

echo "[INFO] Installing the Camunda 8 systemd service on the remote server."
transfer_file "${CONFIG_DIR}/camunda.service" "${MNT_DIR}" camunda.service
transfer_file "${CONFIG_DIR}/camunda-connectors.service" "${MNT_DIR}" camunda-connectors.service

remote_cmd "sudo mv ${MNT_DIR}/camunda.service /etc/systemd/system/camunda.service"
remote_cmd "sudo mv ${MNT_DIR}/camunda-connectors.service /etc/systemd/system/camunda-connectors.service"

# Install and activate Camunda 8 Service
remote_cmd 'sudo systemctl daemon-reload'
remote_cmd 'sudo systemctl enable camunda.service --now'
# restarting the service in case the script is called twice with config changes
remote_cmd 'sudo systemctl restart camunda.service'

# Install and activate Connectors Service
remote_cmd 'sudo systemctl enable camunda-connectors.service --now'
# restarting the service in case the script is called twice with config changes
remote_cmd 'sudo systemctl restart camunda-connectors.service'

#!/bin/bash
set -euo pipefail

USERNAME=${USERNAME:-"camunda"}
ADMIN_USERNAME=${ADMIN_USERNAME:-"ubuntu"}

transfer_file() {
  local source="$1"
  local destination="$2"
  local file_name="$3"

# We cannot directly transfer file to the desition due to ownership issues
  sftp -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" <<EOF
put "${source}"
bye
EOF

echo "[INFO] Changing ownership of file ${file_name}."
remote_cmd "sudo chown ${USERNAME}:${USERNAME} ~/${file_name}"

echo "[INFO] Transferring file ${file_name} to final destination ${destination}."
remote_cmd "sudo mv ~/${file_name} ${destination}"
}

remote_cmd() {
  ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" "$1"
}

check_tool_installed() {
    local tool=$1
    if command -v "$tool" &> /dev/null; then
        echo "[OK] $tool is installed."
    else
        echo "[FAIL] $tool is not installed."
        exit 1
    fi
}

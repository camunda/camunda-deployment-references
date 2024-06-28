#!/bin/bash
set -euo pipefail

transfer_file() {
  source="$1"
  destination="$2"

  sftp -J "admin@${BASTION_IP}" "admin@${ip}" <<EOF
put "${source}" "${destination}"
bye
EOF
}

remote_cmd() {
  ssh -J "admin@${BASTION_IP}" "admin@${ip}" "$1"
}

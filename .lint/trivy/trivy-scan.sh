#!/bin/bash
set -euo pipefail

# ⚠️ Warning: This project is not intended for production use but rather for
# demonstration purposes only. There are no guarantees or warranties provided.
# As such certain Terraform configuration warnings from Trivy have deliberately
# been ignored. For more details, see the
# .trivyignore file in this folder.

# list of the folders that we want to parse, only if a README.md exists and no .trivy_ignore
current_dir=$(pwd)
for dir in $(find ./**/modules -type d -maxdepth 1) $(find examples -type d -maxdepth 1); do
  cd "$current_dir"
  if [ -f "$dir/README.md" ] && ! [ -e "$dir/.trivy_ignore" ]; then
      cd "$dir"
      trivy clean --all
      terraform init || true # try to init if not already initiated
      echo "Scanning terraform module with trivy: $dir"
      trivy config --config "${current_dir}/.lint/trivy/trivy.yaml" --ignorefile "${current_dir}/.lint/trivy/.trivyignore" "."
  fi
done

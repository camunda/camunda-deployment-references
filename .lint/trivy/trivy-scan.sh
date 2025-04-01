#!/bin/bash
set -euxo pipefail

# ⚠️ Warning: This project is not intended for production use but rather for
# demonstration purposes only. There are no guarantees or warranties provided.
# As such certain Terraform configuration warnings from Trivy have deliberately
# been ignored. For more details, see the
# .trivyignore file in this folder.

trivy clean --all

# list of the folders that we want to parse, only if a README.md exists and no .trivy_ignore
for dir in $(find ./**/modules -type d -maxdepth 1) $(find examples -type d -maxdepth 1); do
  if [ -f "$dir/README.md" ] && ! [ -e "$dir/.trivy_ignore" ]; then
      echo "Scanning terraform module with trivy: $dir"
      trivy config --config .lint/trivy/trivy.yaml --ignorefile .lint/trivy/.trivyignore "$dir"
  fi
done

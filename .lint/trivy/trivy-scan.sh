#!/bin/bash
set -euxo pipefail

# list of the folders that we want to parse, only if a README.md exists and no .trivy_ignore
for dir in $(find modules -type d -maxdepth 1) $(find examples -type d -maxdepth 1); do
  if [ -f "$dir/README.md" ] && ! [ -e "$dir/.trivy_ignore" ]; then
      echo "Scanning terraform module with trivy: $dir"
      trivy config --config .lint/trivy/trivy.yaml --ignorefile .trivyignore "$dir"
  fi
done

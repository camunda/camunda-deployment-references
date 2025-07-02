#!/bin/bash
set -euo pipefail

# list of the folders that we want to parse, only if a README.md exists and no .trivy_ignore and at least one tf file is in the directory
# the .test, test and fixtures directories are excluded
find . -type d \( -name .terraform -o -name .test -o -name test -o -name fixtures \) -prune -o -type d -print | while read -r dir; do
  if [ -f "$dir/README.md" ] && [ ! -e "$dir/.trivy_ignore" ] && ls "$dir"/*.tf >/dev/null 2>&1; then
    echo "Scanning terraform module with trivy: $dir"
    # explicitly skip the .terraform, .test, test and fixtures directories, they may still be parts of found directories and scanned recursively
    trivy config --skip-dirs ".terraform,.test,test,fixtures" --config .lint/trivy/trivy.yaml --ignorefile .lint/trivy/.trivyignore "$dir"
  fi
done

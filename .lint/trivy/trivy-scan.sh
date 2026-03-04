#!/bin/bash
set -euo pipefail

# Trivy is run inside a Docker container to limit supply chain exposure.
# The binary was removed from asdf/.tool-versions after corruption concerns (see #1960).

# renovate: datasource=docker depName=ghcr.io/aquasecurity/trivy versioning=semver
TRIVY_VERSION="0.69.3"

REPO_ROOT="$(git rev-parse --show-toplevel)"

# list of the folders that we want to parse, only if a README.md exists and no .trivy_ignore and at least one tf file is in the directory
# the .test, test and fixtures directories are excluded
find . \( -type d \( -name .terraform -o -name .test -o -name test -o -name fixtures \) \) -prune -false -o -type d -print | while read -r dir; do
  if [ -f "$dir/README.md" ] && [ ! -e "$dir/.trivy_ignore" ] && ls "$dir"/*.tf >/dev/null 2>&1; then
    echo "Scanning terraform module with trivy: $dir"
    # explicitly skip the .terraform, .test, test and fixtures directories, they may still be parts of found directories and scanned recursively
    docker run --rm \
      -v "${REPO_ROOT}:/workspace:ro" \
      -w /workspace \
      "ghcr.io/aquasecurity/trivy:${TRIVY_VERSION}" \
      config --skip-dirs ".terraform,.test,test,fixtures" \
      --config /workspace/.lint/trivy/trivy.yaml \
      --ignorefile /workspace/.trivyignore \
      "$dir"
  fi
done

#!/bin/bash
set -euo pipefail

# Download a copy of the reference architecture (RDBMS variant)
# TODO: [release-duty] before the release, update this!
BRANCH="main"

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the desired directory
cd "camunda-deployment-references/azure/kubernetes/aks-single-region-rdbms/" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

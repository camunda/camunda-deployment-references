#!/bin/bash
set -euo pipefail

# Download a copy of the reference architecture
BRANCH="stable/8.9"

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the repository root (OpenShift guides require files from multiple directories)
cd "camunda-deployment-references" || exit 1
echo "You are now in the reference architecture directory $(pwd)."
echo "Operator-based infrastructure: generic/kubernetes/operator-based/"
echo "OpenShift-specific configuration: generic/openshift/single-region/"

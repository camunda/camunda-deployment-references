#!/bin/bash

# Download a copy of the reference architecture
BRANCH="stable/8.8"

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the desired directory
cd "camunda-deployment-references/generic/kubernetes/operator-based" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

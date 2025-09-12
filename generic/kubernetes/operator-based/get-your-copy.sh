#!/bin/bash

# Download a copy of the reference architecture
#BRANCH="main"  # TODO: [release-duty] before the release, update this!
BRANCH="feature/operator-playground"  # TODO: revert this

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the desired directory
cd "camunda-deployment-references/generic/kubernetes/operator-based" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

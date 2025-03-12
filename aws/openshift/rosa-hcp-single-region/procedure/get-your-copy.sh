#!/bin/bash

# Download a copy of the reference architecture
BRANCH="feature/integrate-tests-rosa"  # TODO: Change the branch to 8.6 after the merge

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the desired directory
cd "camunda-deployment-references/aws/openshift/rosa-hcp-single-region" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

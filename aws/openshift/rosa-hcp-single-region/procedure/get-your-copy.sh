#!/bin/bash

# Download a copy of the reference architecture
BRANCH="main"  # TODO: Change the branch to main then [release-duty] to 8.7

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the desired directory
cd "camunda-deployment-references/aws/openshift/rosa-hcp-single-region" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

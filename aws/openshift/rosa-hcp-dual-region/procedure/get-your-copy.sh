#!/bin/bash

# Download a copy of the reference architecture
BRANCH="feature/migrate-dual-region-rosa"  # TODO: [release-duty] before the release, update this!

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the desired directory
cd "camunda-deployment-references/aws/openshift/rosa-hcp-dual-region" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

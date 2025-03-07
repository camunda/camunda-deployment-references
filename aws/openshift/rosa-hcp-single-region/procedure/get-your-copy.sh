#!/bin/bash
# Download a copy of the reference architecture

# URL of the GitHub repository and specific branch
REPO_URL="https://github.com/camunda/camunda-deployment-references"
BRANCH="feature/integrate-tests-rosa"  # TODO: Change the branch to 8.6

# Download the zip file from the specified branch
BRANCH_HYPHENATED="${BRANCH//\//-}"
curl -L "${REPO_URL}/archive/refs/heads/${BRANCH}.zip" -o "ra-${BRANCH_HYPHENATED}.zip"
unzip "ra-${BRANCH_HYPHENATED}.zip"

# Navigate to the specific directory
cd "camunda-deployment-references-${BRANCH_HYPHENATED}/aws/openshift/rosa-hcp-single-region" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

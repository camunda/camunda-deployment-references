#!/bin/bash

# Download a copy of the reference architecture
BRANCH="feature/integrate-tests-rosa"  # TODO: Change the branch to 8.6

# Download the zip file from the specified branch
curl -L "https://github.com/camunda/camunda-deployment-references/archive/refs/heads/${BRANCH}.zip" -o "camunda-ra.zip"


unzip "camunda-ra.zip" -d temp_extract

# Identify the root folder created by GitHub
ROOT_FOLDER=$(find temp_extract -mindepth 1 -maxdepth 1 -type d | head -n 1)

# Move only the contents into the target directory
mkdir -p camunda-deployment-references
mv temp_extract/"$ROOT_FOLDER"/* camunda-deployment-references/
rm -Rf temp_extract camunda-ra.zip

# Navigate to the specific directory
cd "camunda-deployment-references/aws/openshift/rosa-hcp-single-region" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

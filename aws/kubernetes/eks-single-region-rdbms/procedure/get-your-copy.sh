#!/bin/bash

# Download a copy of the reference architecture
# CI overrides the branch so the suite copies the revision under test; a
# reference architecture introduced by a pull request is not on the published
# branch yet, and the clone would land on a tree without this directory.
BRANCH="${REF_ARCH_BRANCH:-stable/8.9}"

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

# Navigate to the desired directory
cd "camunda-deployment-references/aws/kubernetes/eks-single-region-rdbms" || exit 1
echo "You are now in the reference architecture directory $(pwd)."

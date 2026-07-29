#!/bin/bash
set -euo pipefail

# TODO [release-duty]: pin to the released branch (stable/8.10) at release time.
BRANCH="main"

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

cd camunda-deployment-references/aws/kubernetes/eks-multi-region-rdbms || exit 1

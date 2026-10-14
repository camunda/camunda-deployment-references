#!/usr/bin/env bash
set -euo pipefail

BRANCH="stable/8.10"

git clone --depth 1 --branch "$BRANCH" https://github.com/camunda/camunda-deployment-references.git

cd camunda-deployment-references/aws/kubernetes/eks-multi-region-rdbms || exit 1

#!/usr/bin/env bash
#
# 01-setup-fis-experiment-role.sh
#
# One-time setup: Creates the IAM role that AWS FIS assumes to perform
# network disruptions (modify NACLs, etc.) during experiments.
#
# Prerequisites:
#   - Logged in with a role allowed to create IAM roles
#   - AWS CLI v2, jq
#
# Usage:
#   ./setup/01-setup-fis-experiment-role.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="${SCRIPT_DIR}/../policies"

AWS_REGION="${AWS_REGION:-eu-west-2}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"

echo "=== Setting up FIS Experiment Role ==="
echo "Role name: ${FIS_EXPERIMENT_ROLE}"
echo "Region:    ${AWS_REGION}"
echo ""

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"

# The confused-deputy conditions live in this document, so it has to be applied
# on every run and not only at creation: a role created before they were added
# would otherwise keep trusting fis.amazonaws.com unconditionally forever.
TRUST_POLICY=$(sed "s/ACCOUNT_ID_PLACEHOLDER/${ACCOUNT_ID}/" "${POLICIES_DIR}/fis-experiment-role-trust.json")

if aws iam get-role --role-name "${FIS_EXPERIMENT_ROLE}" &>/dev/null; then
  echo ""
  echo "Role '${FIS_EXPERIMENT_ROLE}' already exists. Updating policies..."

  aws iam update-assume-role-policy \
    --role-name "${FIS_EXPERIMENT_ROLE}" \
    --policy-document "${TRUST_POLICY}"

  echo "Trust policy updated."
else
  echo ""
  echo "Creating role '${FIS_EXPERIMENT_ROLE}'..."

  aws iam create-role \
    --role-name "${FIS_EXPERIMENT_ROLE}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --tags Key=managed_by,Value=chaos-tests Key=repository,Value=camunda/camunda-deployment-references \
    --output text --query 'Role.Arn'

  echo "Role created."
fi

# Attach permissions policy
echo "Attaching permissions policy..."
aws iam put-role-policy \
  --role-name "${FIS_EXPERIMENT_ROLE}" \
  --policy-name FIS-Network-Disrupt-Policy \
  --policy-document "file://${POLICIES_DIR}/fis-experiment-role-perms.json"

echo ""
echo "=== FIS Experiment Role setup complete ==="
echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${FIS_EXPERIMENT_ROLE}"
echo ""
echo "Next step: Run ./setup/02-setup-fis-admin-role.sh"

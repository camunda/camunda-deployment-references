#!/usr/bin/env bash
#
# 01-setup-fis-experiment-role.sh
#
# One-time setup: Creates the IAM role that AWS FIS assumes to perform
# network disruptions (modify NACLs, etc.) during experiments.
#
# Prerequisites:
#   - Logged in via AWS SSO as SystemAdministrator
#   - AWS CLI v2, jq
#
# Usage:
#   ./setup/01-setup-fis-experiment-role.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="${SCRIPT_DIR}/../policies"

AWS_REGION="${AWS_REGION:-eu-west-1}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"

echo "=== Setting up FIS Experiment Role ==="
echo "Role name: ${FIS_EXPERIMENT_ROLE}"
echo "Region:    ${AWS_REGION}"
echo ""

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"

# Check if role already exists
if aws iam get-role --role-name "${FIS_EXPERIMENT_ROLE}" &>/dev/null; then
  echo ""
  echo "Role '${FIS_EXPERIMENT_ROLE}' already exists. Updating policies..."
else
  echo ""
  echo "Creating role '${FIS_EXPERIMENT_ROLE}'..."

  # Build trust policy with actual account ID
  TRUST_POLICY=$(sed "s/ACCOUNT_ID_PLACEHOLDER/${ACCOUNT_ID}/" "${POLICIES_DIR}/fis-experiment-role-trust.json")

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

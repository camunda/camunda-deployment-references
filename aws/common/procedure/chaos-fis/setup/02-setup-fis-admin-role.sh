#!/usr/bin/env bash
#
# 02-setup-fis-admin-role.sh
#
# One-time setup: Creates the FIS-Admin IAM role that SSO users assume
# to create and run FIS experiments.
#
# This role's trust policy allows ANY user assuming the SystemAdministrator
# SSO role to assume it, so multiple team members can use it.
#
# Prerequisites:
#   - Logged in via AWS SSO as SystemAdministrator
#   - AWS CLI v2, jq
#   - 01-setup-fis-experiment-role.sh has been run
#
# Usage:
#   ./setup/02-setup-fis-admin-role.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="${SCRIPT_DIR}/../policies"

AWS_REGION="${AWS_REGION:-eu-west-1}"
FIS_ADMIN_ROLE="${FIS_ADMIN_ROLE:-FIS-Admin}"

echo "=== Setting up FIS Admin Role ==="
echo "Role name: ${FIS_ADMIN_ROLE}"
echo "Region:    ${AWS_REGION}"
echo ""

# Get account ID and current SSO role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo "Account ID:  ${ACCOUNT_ID}"
echo "Caller ARN:  ${CALLER_ARN}"

# Extract the SSO role name from the caller ARN
# e.g., arn:aws:sts::123456:assumed-role/AWSReservedSSO_SystemAdministrator_abc123/user@email
SSO_ROLE_NAME=$(echo "${CALLER_ARN}" | grep -oP 'assumed-role/\K[^/]+')
echo "SSO Role:    ${SSO_ROLE_NAME}"

# Get the actual IAM role ARN (SSO roles live under aws-reserved path)
SSO_ROLE_ARN=$(aws iam get-role --role-name "${SSO_ROLE_NAME}" --query 'Role.Arn' --output text)
echo "SSO Role ARN: ${SSO_ROLE_ARN}"

# Build the trust policy — allows the SSO SystemAdministrator role to assume FIS-Admin
# Uses a wildcard on the session name so any SSO user with this role can assume it
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${SSO_ROLE_ARN}"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/department": []
        }
      }
    }
  ]
}
EOF
)

# Simplified trust policy without conditions (the principal ARN is sufficient)
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${SSO_ROLE_ARN}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

# Check if role already exists
if aws iam get-role --role-name "${FIS_ADMIN_ROLE}" &>/dev/null; then
  echo ""
  echo "Role '${FIS_ADMIN_ROLE}' already exists. Updating trust and permissions policies..."

  aws iam update-assume-role-policy \
    --role-name "${FIS_ADMIN_ROLE}" \
    --policy-document "${TRUST_POLICY}"

  echo "Trust policy updated."
else
  echo ""
  echo "Creating role '${FIS_ADMIN_ROLE}'..."

  aws iam create-role \
    --role-name "${FIS_ADMIN_ROLE}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --tags Key=managed_by,Value=chaos-tests Key=repository,Value=camunda/camunda-deployment-references \
    --output text --query 'Role.Arn'

  echo "Role created."
fi

# Attach permissions policy
echo "Attaching permissions policy..."
aws iam put-role-policy \
  --role-name "${FIS_ADMIN_ROLE}" \
  --policy-name FIS-Admin-Access \
  --policy-document "file://${POLICIES_DIR}/fis-admin-role-perms.json"

echo ""
echo "=== FIS Admin Role setup complete ==="
echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${FIS_ADMIN_ROLE}"
echo ""
echo "Any user logged in as '${SSO_ROLE_NAME}' can now assume this role."
echo ""
echo "Next step: source ./experiments/assume-fis-role.sh"

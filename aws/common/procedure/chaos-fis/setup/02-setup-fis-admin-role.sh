#!/usr/bin/env bash
#
# 02-setup-fis-admin-role.sh
#
# One-time setup: Creates the FIS-Admin IAM role that SSO users assume
# to create and run FIS experiments.
#
# The trust policy names whatever role you are logged in as, so every team
# member sharing that role can assume FIS-Admin with no per-user setup.
#
# Prerequisites:
#   - Logged in with a role allowed to create IAM roles
#   - AWS CLI v2, jq
#   - 01-setup-fis-experiment-role.sh has been run
#
# Usage:
#   ./setup/02-setup-fis-admin-role.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="${SCRIPT_DIR}/../policies"

FIS_ADMIN_ROLE="${FIS_ADMIN_ROLE:-FIS-Admin}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo "Usage: $0"
      echo ""
      echo "Creates the role team members assume to run experiments, trusting"
      echo "whatever role you are currently logged in as. Safe to re-run: an"
      echo "existing role has both documents refreshed."
      echo ""
      echo "Environment overrides:"
      echo "  FIS_ADMIN_ROLE        Role name (default: FIS-Admin)"
      echo "  FIS_EXPERIMENT_ROLE   Role named in the iam:PassRole grant (default: FIS-Experiment-Role)"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== Setting up FIS Admin Role ==="
echo "Role name: ${FIS_ADMIN_ROLE}"
echo ""

# Get account ID and current SSO role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo "Account ID:  ${ACCOUNT_ID}"
echo "Caller ARN:  ${CALLER_ARN}"

# Extract the role name out of the caller ARN, which for an assumed role looks
# like arn:aws:sts::<account>:assumed-role/<role-name>/<session-name>. Done with
# sed rather than `grep -oP`, whose \K is a GNU extension the BSD grep on macOS
# does not have.
SSO_ROLE_NAME=$(printf '%s' "${CALLER_ARN}" | sed -n 's|.*:assumed-role/\([^/]*\)/.*|\1|p')

if [ -z "${SSO_ROLE_NAME}" ]; then
  echo "ERROR: ${CALLER_ARN} is not an assumed role, so there is no role to trust." >&2
  echo "Log in with the role you want to grant (for example 'aws sso login --profile <profile>')." >&2
  exit 1
fi

echo "Caller role: ${SSO_ROLE_NAME}"

# Get the actual IAM role ARN (SSO roles live under aws-reserved path)
SSO_ROLE_ARN=$(aws iam get-role --role-name "${SSO_ROLE_NAME}" --query 'Role.Arn' --output text)
echo "Caller role ARN: ${SSO_ROLE_ARN}"

# Anyone who can assume the caller's own role can assume FIS-Admin. That is the
# point: the team shares one role rather than one grant per person.
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

# The PassRole statement has to name the experiment role that the create
# scripts actually put in roleArn. Leaving the literal default in the policy
# file would let setup succeed and start-experiment fail later with an
# iam:PassRole AccessDenied, which is a long way from the cause.
ADMIN_POLICY=$(sed "s/FIS_EXPERIMENT_ROLE_NAME/${FIS_EXPERIMENT_ROLE}/g" \
  "${POLICIES_DIR}/fis-admin-role-perms.json")

aws iam put-role-policy \
  --role-name "${FIS_ADMIN_ROLE}" \
  --policy-name FIS-Admin-Access \
  --policy-document "${ADMIN_POLICY}"

echo ""
echo "=== FIS Admin Role setup complete ==="
echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${FIS_ADMIN_ROLE}"
echo ""
echo "Any user logged in as '${SSO_ROLE_NAME}' can now assume this role."
echo ""
echo "Next step: source ./experiments/assume-fis-role.sh"

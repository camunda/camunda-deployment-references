#!/usr/bin/env bash
#
# assume-fis-role.sh
#
# Assumes the FIS-Admin IAM role and exports temporary credentials.
# Must be sourced (not executed) so the env vars are set in the current shell:
#
#   source ./experiments/assume-fis-role.sh
#
# The assumed session lasts 1 hour by default.
#
# To return to your SSO role:
#   unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
#

# Guard: must be sourced, not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: This script must be sourced, not executed."
  echo "Usage: source ./experiments/assume-fis-role.sh"
  exit 1
fi

FIS_ADMIN_ROLE="${FIS_ADMIN_ROLE:-FIS-Admin}"
AWS_REGION="${AWS_REGION:-eu-west-2}"

# Clear any previously assumed role credentials first
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

echo "=== Assuming FIS-Admin role ==="

# Get account ID (using SSO credentials)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [[ -z "${ACCOUNT_ID}" || "${ACCOUNT_ID}" == "None" ]]; then
  echo "ERROR: Could not get AWS account ID. Are you logged in via SSO?"
  echo "  Run: aws sso login --profile <your-profile>"
  return 1
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FIS_ADMIN_ROLE}"
SESSION_NAME="fis-$(whoami | tr '.' '-')-$(date +%s)"

echo "Role ARN: ${ROLE_ARN}"
echo "Session:  ${SESSION_NAME}"

# Assume the role
if ! CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "${SESSION_NAME}" \
  --duration-seconds 3600 \
  --output json 2>&1); then
  echo "ERROR: Failed to assume role."
  echo "${CREDS}"
  return 1
fi

# Export credentials
export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "${CREDS}" | jq -r '.Credentials.SessionToken')

# Verify. The status matters: this file is sourced, so it runs without set -e,
# and a discarded failure here would announce success while leaving the caller
# with credentials that do not work.
if ! IDENTITY=$(aws sts get-caller-identity --output json 2>&1); then
  echo "ERROR: the assumed credentials were rejected." >&2
  echo "${IDENTITY}" >&2
  return 1
fi

echo ""
echo "Assumed role successfully:"
echo "${IDENTITY}" | jq '.'
echo ""
echo "Session expires in 1 hour."
echo "To return to SSO role: unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN"

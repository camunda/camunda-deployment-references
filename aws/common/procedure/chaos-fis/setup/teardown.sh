#!/usr/bin/env bash
#
# teardown.sh
#
# Removes all IAM roles and policies created by the setup scripts.
#
# Prerequisites:
#   - Logged in via AWS SSO as SystemAdministrator
#   - Must NOT have assumed FIS-Admin role (unset credentials first)
#
# Usage:
#   ./setup/teardown.sh
#

set -euo pipefail

FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"
FIS_ADMIN_ROLE="${FIS_ADMIN_ROLE:-FIS-Admin}"

echo "=== Tearing down FIS IAM resources ==="
echo ""
echo "This will delete:"
echo "  - Role: ${FIS_ADMIN_ROLE}"
echo "  - Role: ${FIS_EXPERIMENT_ROLE}"
echo ""
read -p "Are you sure? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Delete FIS-Admin role
echo ""
echo "--- Removing ${FIS_ADMIN_ROLE} ---"
if aws iam get-role --role-name "${FIS_ADMIN_ROLE}" &>/dev/null; then
  # Delete inline policies
  POLICIES=$(aws iam list-role-policies --role-name "${FIS_ADMIN_ROLE}" --query 'PolicyNames' --output text)
  for POLICY in ${POLICIES}; do
    echo "  Deleting inline policy: ${POLICY}"
    aws iam delete-role-policy --role-name "${FIS_ADMIN_ROLE}" --policy-name "${POLICY}"
  done

  # Detach managed policies
  ATTACHED=$(aws iam list-attached-role-policies --role-name "${FIS_ADMIN_ROLE}" --query 'AttachedPolicies[].PolicyArn' --output text)
  for ARN in ${ATTACHED}; do
    echo "  Detaching managed policy: ${ARN}"
    aws iam detach-role-policy --role-name "${FIS_ADMIN_ROLE}" --policy-arn "${ARN}"
  done

  aws iam delete-role --role-name "${FIS_ADMIN_ROLE}"
  echo "  Deleted role: ${FIS_ADMIN_ROLE}"
else
  echo "  Role ${FIS_ADMIN_ROLE} not found, skipping."
fi

# Delete FIS-Experiment-Role
echo ""
echo "--- Removing ${FIS_EXPERIMENT_ROLE} ---"
if aws iam get-role --role-name "${FIS_EXPERIMENT_ROLE}" &>/dev/null; then
  # Delete inline policies
  POLICIES=$(aws iam list-role-policies --role-name "${FIS_EXPERIMENT_ROLE}" --query 'PolicyNames' --output text)
  for POLICY in ${POLICIES}; do
    echo "  Deleting inline policy: ${POLICY}"
    aws iam delete-role-policy --role-name "${FIS_EXPERIMENT_ROLE}" --policy-name "${POLICY}"
  done

  # Detach managed policies
  ATTACHED=$(aws iam list-attached-role-policies --role-name "${FIS_EXPERIMENT_ROLE}" --query 'AttachedPolicies[].PolicyArn' --output text)
  for ARN in ${ATTACHED}; do
    echo "  Detaching managed policy: ${ARN}"
    aws iam detach-role-policy --role-name "${FIS_EXPERIMENT_ROLE}" --policy-arn "${ARN}"
  done

  aws iam delete-role --role-name "${FIS_EXPERIMENT_ROLE}"
  echo "  Deleted role: ${FIS_EXPERIMENT_ROLE}"
else
  echo "  Role ${FIS_EXPERIMENT_ROLE} not found, skipping."
fi

echo ""
echo "=== Teardown complete ==="

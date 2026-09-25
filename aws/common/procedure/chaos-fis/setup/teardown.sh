#!/usr/bin/env bash
#
# teardown.sh
#
# Removes everything this procedure creates: the FIS experiment templates, the
# CloudWatch log group they log to, and the two IAM roles.
#
# The order is not cosmetic. Deleting an experiment template needs
# fis:DeleteExperimentTemplate, and once FIS-Admin is gone the only principal
# left holding it is you, so the templates go first and the roles last. The
# previous version deleted the roles first and left the templates stranded.
#
# Run it with your own credentials, not with FIS-Admin assumed: FIS-Admin is
# not allowed to delete IAM roles. If you sourced assume-fis-role.sh, run
# `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` first.
#
# Usage:
#   ./setup/teardown.sh [--region <region>] [--yes]
#
# Options:
#   --region   AWS region holding the templates and log group (default: eu-west-2)
#   --yes      Skip the confirmation prompt
#

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-2}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"
FIS_ADMIN_ROLE="${FIS_ADMIN_ROLE:-FIS-Admin}"
LOG_GROUP="${FIS_LOG_GROUP:-/fis/chaos-tests}"
MANAGED_BY="chaos-tests"
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --region) AWS_REGION="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--region <region>] [--yes]"
      echo ""
      echo "  --region   AWS region holding the templates and log group (default: eu-west-2)"
      echo "  --yes      Skip the confirmation prompt"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

TEMPLATE_IDS=$(aws fis list-experiment-templates \
  --region "${AWS_REGION}" \
  --query "experimentTemplates[?tags.managed_by=='${MANAGED_BY}'].id" \
  --output text 2> /dev/null || echo "")
TEMPLATE_IDS=${TEMPLATE_IDS//None/}

echo "=== Tearing down the FIS chaos testing resources ==="
echo ""
echo "Region: ${AWS_REGION}"
echo ""
echo "This will delete:"
echo "  - Experiment templates tagged managed_by=${MANAGED_BY}: ${TEMPLATE_IDS:-none found}"
echo "  - Log group: ${LOG_GROUP}"
echo "  - Role:      ${FIS_ADMIN_ROLE}"
echo "  - Role:      ${FIS_EXPERIMENT_ROLE}"
echo ""
echo "Running experiments are not stopped. Stop them first with experiment-stop.sh,"
echo "or their network disruption outlives the template that described it."
echo ""

if [[ "${ASSUME_YES}" != "true" ]]; then
  read -rp "Are you sure? (y/N) " -n 1 REPLY
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# --- Experiment templates, before the role that can delete them ---
echo ""
echo "--- Removing experiment templates ---"
if [[ -n "${TEMPLATE_IDS// /}" ]]; then
  for TEMPLATE_ID in ${TEMPLATE_IDS}; do
    echo "  Deleting template: ${TEMPLATE_ID}"
    aws fis delete-experiment-template --id "${TEMPLATE_ID}" --region "${AWS_REGION}" > /dev/null
  done
else
  echo "  No template tagged managed_by=${MANAGED_BY}, skipping."
fi

# --- Network ACLs an interrupted experiment left behind ---
#
# FIS restores the original association when an action ends, but an experiment
# that is killed rather than stopped can leave its clone attached, and the deny
# rules attached with it. Nothing else reclaims these: cloud-nuke does not know
# the tag, and the subnet keeps answering nothing until someone notices.
echo ""
echo "--- Checking for network ACLs left behind by FIS ---"
LEAKED_ACLS=$(aws ec2 describe-network-acls \
  --region "${AWS_REGION}" \
  --filters Name=tag:managedByFIS,Values=true \
  --query 'NetworkAcls[].NetworkAclId' \
  --output text 2> /dev/null || echo "")
LEAKED_ACLS=${LEAKED_ACLS//None/}

if [[ -n "${LEAKED_ACLS// /}" ]]; then
  echo "  WARNING: FIS-managed network ACLs still exist: ${LEAKED_ACLS}"
  echo "  If one is still associated with a subnet, that subnet is still cut off."
  echo "  Inspect before deleting — the original association has to be restored first:"
  for ACL_ID in ${LEAKED_ACLS}; do
    echo "    aws ec2 describe-network-acls --network-acl-ids ${ACL_ID} --region ${AWS_REGION}"
  done
else
  echo "  None found."
fi

# --- Log group ---
echo ""
echo "--- Removing log group ${LOG_GROUP} ---"
if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP}" --region "${AWS_REGION}" \
  --query "logGroups[?logGroupName=='${LOG_GROUP}'].logGroupName" --output text 2> /dev/null | grep -q .; then
  aws logs delete-log-group --log-group-name "${LOG_GROUP}" --region "${AWS_REGION}"
  echo "  Deleted."
else
  echo "  Not found, skipping."
fi

# --- IAM roles, last ---
delete_role() {
  local role_name="$1"

  echo ""
  echo "--- Removing ${role_name} ---"
  if ! aws iam get-role --role-name "${role_name}" > /dev/null 2>&1; then
    echo "  Role ${role_name} not found, skipping."
    return 0
  fi

  local policies attached
  # `--output text` prints the literal "None" when a query matches nothing, so
  # an unfiltered loop would call delete-role-policy --policy-name None and
  # `set -e` would abort before either role is deleted. Both roles here carry
  # inline policies and no managed ones, which is exactly that case.
  policies=$(aws iam list-role-policies --role-name "${role_name}" --query 'PolicyNames' --output text)
  for policy in ${policies}; do
    [ "${policy}" = "None" ] && continue
    echo "  Deleting inline policy: ${policy}"
    aws iam delete-role-policy --role-name "${role_name}" --policy-name "${policy}"
  done

  attached=$(aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text)
  for arn in ${attached}; do
    [ "${arn}" = "None" ] && continue
    echo "  Detaching managed policy: ${arn}"
    aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${arn}"
  done

  aws iam delete-role --role-name "${role_name}"
  echo "  Deleted role: ${role_name}"
}

delete_role "${FIS_ADMIN_ROLE}"
delete_role "${FIS_EXPERIMENT_ROLE}"

echo ""
echo "=== Teardown complete ==="

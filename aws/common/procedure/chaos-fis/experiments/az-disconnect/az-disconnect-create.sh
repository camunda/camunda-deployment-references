#!/usr/bin/env bash
#
# az-disconnect-create.sh
#
# Creates an FIS experiment template that disconnects one Availability Zone
# by disrupting network connectivity on the target private subnet(s).
# Disconnects full subnet, so all benchmarks running in that subnet are
# affected. Hence it is not recommended to run in "prod".
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Setup scripts have been run
#
# Usage:
#   ./experiments/az-disconnect/az-disconnect-create.sh --az eu-west-2b --duration PT10M
#   ./experiments/az-disconnect/az-disconnect-create.sh --az eu-west-2a --duration PT30M --name my-test
#
# Options:
#   --az        Target AZ to disconnect (required, e.g., eu-west-2a)
#   --duration  Disruption duration in ISO 8601 (default: PT10M = 10 minutes)
#   --name      Experiment template name tag (default: az-disconnect-dev)
#   --vpc       VPC name tag to find subnets (default: camunda-vpc)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

# --- Defaults ---
AWS_REGION="${AWS_REGION:-eu-west-2}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"
VPC_NAME="${VPC_NAME:-camunda-vpc}"
DURATION="PT10M"
TEMPLATE_NAME="1-az-disconnect-dev"
TARGET_AZ=""
LOG_GROUP="${FIS_LOG_GROUP:-/fis/chaos-tests}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --az)        TARGET_AZ="$2";      shift 2 ;;
    --duration)  DURATION="$2";       shift 2 ;;
    --name)      TEMPLATE_NAME="$2";  shift 2 ;;
    --vpc)       VPC_NAME="$2";       shift 2 ;;
    --log-group) LOG_GROUP="$2";      shift 2 ;;
    -h|--help)
      echo "Usage: $0 --az <AZ_NAME> [--duration <ISO8601>] [--name <NAME>] [--vpc <VPC_NAME>]"
      echo ""
      echo "Options:"
      echo "  --az        Target AZ to disconnect (required, e.g., eu-west-2a)"
      echo "  --duration  Disruption duration in ISO 8601 (default: PT10M)"
      echo "  --name      Experiment template name tag (default: az-disconnect-dev)"
      echo "  --vpc       VPC name tag (default: camunda-vpc)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${TARGET_AZ}" ]]; then
  echo "ERROR: --az is required."
  echo "Usage: $0 --az eu-west-2b [--duration PT10M]"
  exit 1
fi

echo "=== Creating AZ Disconnect Experiment Template ==="
echo "Target AZ:     ${TARGET_AZ}"
echo "Duration:      ${DURATION}"
echo "Template name: ${TEMPLATE_NAME}"
echo "VPC:           ${VPC_NAME}"
echo "Region:        ${AWS_REGION}"
echo ""

# --- Get account ID ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"

# --- Find VPC ID ---
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region "${AWS_REGION}")

if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
  echo "ERROR: VPC '${VPC_NAME}' not found in ${AWS_REGION}"
  exit 1
fi
echo "VPC ID: ${VPC_ID}"

# --- Find private subnets in the target AZ ---
# A subnet is public when its route table sends traffic to an internet gateway.
# MapPublicIpOnLaunch is not a reliable signal: the reference VPC's public
# subnets have it off too, which would pull them into the blast radius.
# ponytail: only explicit route-table associations are checked, which is how
# the reference VPC is built; a main route table with an IGW route is not.
PUBLIC_SUBNET_IDS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=route.gateway-id,Values=igw-*" \
  --query "RouteTables[].Associations[].SubnetId" \
  --output text \
  --region "${AWS_REGION}" | tr '\t\n' '  ')

SUBNET_IDS=""
for SUBNET_ID in $(aws ec2 describe-subnets \
  --filters \
    "Name=vpc-id,Values=${VPC_ID}" \
    "Name=availability-zone,Values=${TARGET_AZ}" \
  --query "Subnets[].SubnetId" \
  --output text \
  --region "${AWS_REGION}"); do
  [[ " ${PUBLIC_SUBNET_IDS} " == *" ${SUBNET_ID} "* ]] || SUBNET_IDS="${SUBNET_IDS} ${SUBNET_ID}"
done
SUBNET_IDS="${SUBNET_IDS# }"

if [[ -z "${SUBNET_IDS}" ]]; then
  echo "ERROR: No private subnets found in AZ '${TARGET_AZ}' within VPC '${VPC_ID}'"
  echo ""
  echo "Subnets in this VPC:"
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[].[AvailabilityZone,SubnetId,CidrBlock]" \
    --output table \
    --region "${AWS_REGION}"
  exit 1
fi

echo "Target private subnets in ${TARGET_AZ}:"

# Build the resource ARNs array
RESOURCE_ARNS=""
for SUBNET_ID in ${SUBNET_IDS}; do
  echo "  - ${SUBNET_ID}"
  if [[ -n "${RESOURCE_ARNS}" ]]; then
    RESOURCE_ARNS="${RESOURCE_ARNS},"
  fi
  RESOURCE_ARNS="${RESOURCE_ARNS}\"arn:aws:ec2:${AWS_REGION}:${ACCOUNT_ID}:subnet/${SUBNET_ID}\""
done

echo ""

# --- Ensure CloudWatch log group exists ---
ensure_log_group "${LOG_GROUP}"

# --- Build and create the experiment template ---
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FIS_EXPERIMENT_ROLE}"
LOG_GROUP_ARN="arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"

TEMPLATE_FILE=$(mktemp)
trap 'rm -f "${TEMPLATE_FILE}"' EXIT
cat > "${TEMPLATE_FILE}" << EOF
{
  "description": "Disconnect AZ ${TARGET_AZ} - isolate AZ network connectivity for ${DURATION}",
  "targets": {
    "target-subnets": {
      "resourceType": "aws:ec2:subnet",
      "resourceArns": [${RESOURCE_ARNS}],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disconnect-az": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "scope": "availability-zone",
        "duration": "${DURATION}"
      },
      "targets": {
        "Subnets": "target-subnets"
      }
    }
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ],
  "logConfiguration": {
    "cloudWatchLogsConfiguration": {
      "logGroupArn": "${LOG_GROUP_ARN}"
    },
    "logSchemaVersion": 2
  },
  "roleArn": "${ROLE_ARN}",
  "tags": {
    "Name": "${TEMPLATE_NAME}",
    "target_az": "${TARGET_AZ}",
    "duration": "${DURATION}",
    "environment": "dev",
    "managed_by": "chaos-tests",
    "repository": "camunda/camunda-deployment-references"
  }
}
EOF

# --- Delete existing template and create new one ---
delete_template_by_name "${TEMPLATE_NAME}"
create_template "${TEMPLATE_FILE}"

echo ""
echo "=== Experiment template created ==="
echo "Template ID: ${TEMPLATE_ID}"
echo "Name:        ${TEMPLATE_NAME}"
echo ""
echo "To run the experiment:"
echo "  ./experiments/az-disconnect/az-disconnect-run.sh --name ${TEMPLATE_NAME}"
echo "  # or"
echo "  ./experiments/az-disconnect/az-disconnect-run.sh --id ${TEMPLATE_ID}"

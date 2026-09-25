#!/usr/bin/env bash
#
# broker-disconnect-create.sh
#
# Creates an FIS experiment template that disconnects a single Camunda broker
# (ECS task) by disrupting network connectivity on its Elastic Network Interface.
#
# Unlike az-disconnect-create.sh which disconnects an entire AZ (affecting all
# benchmarks), this targets a single broker ENI belonging to a specific benchmark,
# leaving other benchmarks unaffected.
#
# How it works:
#   1. Finds the ECS service for the given deployment prefix
#   2. Lists running tasks and picks one (or the one in the specified AZ)
#   3. Resolves the task's ENI (Elastic Network Interface)
#   4. Creates an FIS experiment template that uses aws:network:disrupt-connectivity
#      scoped to the ENI's subnet, targeting only that subnet
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Setup scripts have been run
#   - Benchmark ECS service is running
#
# Usage:
#   ./experiments/broker-disconnect/broker-disconnect-create.sh --prefix camunda --duration PT10M
#   ./experiments/broker-disconnect/broker-disconnect-create.sh --prefix camunda --az eu-west-2b --duration PT5M
#
# Options:
#   --prefix        Deployment prefix, var.prefix of the ECS reference architecture (required, e.g. camunda)
#   --az            Target a broker in this AZ (default: random task)
#   --duration      Disruption duration in ISO 8601 (default: PT10M = 10 minutes)
#   --name          Experiment template name tag (default: broker-disconnect-<prefix>)
#   --cluster       ECS cluster name (default: camunda-cluster)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

# --- Defaults ---
AWS_REGION="${AWS_REGION:-eu-west-2}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"
ECS_CLUSTER="${ECS_CLUSTER:-camunda-cluster}"
DURATION="PT10M"
PREFIX=""
TARGET_AZ=""
TEMPLATE_NAME=""
LOG_GROUP="${FIS_LOG_GROUP:-/fis/chaos-tests}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --prefix)        PREFIX="$2";        shift 2 ;;
    --az)            TARGET_AZ="$2";     shift 2 ;;
    --duration)      DURATION="$2";      shift 2 ;;
    --name)          TEMPLATE_NAME="$2"; shift 2 ;;
    --cluster)       ECS_CLUSTER="$2";   shift 2 ;;
    --log-group)     LOG_GROUP="$2";     shift 2 ;;
    -h|--help)
      echo "Usage: $0 --prefix <PREFIX> [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --prefix        Deployment prefix (required, e.g. camunda)"
      echo "  --az            Target a broker in this AZ (default: random task)"
      echo "  --duration      Disruption duration in ISO 8601 (default: PT10M)"
      echo "  --name          Template name tag (default: broker-disconnect-<prefix>)"
      echo "  --cluster       ECS cluster name (default: camunda-cluster)"
      echo "  --log-group     CloudWatch log group for FIS logs (default: /fis/chaos-tests)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${PREFIX}" ]]; then
  echo "ERROR: --prefix is required."
  echo "Usage: $0 --prefix camunda [--duration PT10M]"
  exit 1
fi

if [[ -z "${TEMPLATE_NAME}" ]]; then
  TEMPLATE_NAME="broker-disconnect-${PREFIX}"
fi

echo "=== Creating Broker Disconnect Experiment Template ==="
echo "Deployment prefix: ${PREFIX}"
echo "ECS cluster:      ${ECS_CLUSTER}"
echo "Duration:         ${DURATION}"
echo "Template name:    ${TEMPLATE_NAME}"
echo "Region:           ${AWS_REGION}"
echo "Log group:        ${LOG_GROUP}"
echo ""

# --- Get account ID ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"

# --- Discover ECS service and tasks ---
discover_ecs_service "${PREFIX}"
# shellcheck disable=SC2119 # $1 is optional and documented with a default; "$@" would pass this script's CLI flags instead
list_running_tasks
describe_tasks_with_network
select_task_by_az_or_random "${TARGET_AZ}"

TARGET_ENI=$(echo "${TARGET_TASK}" | jq -r '.eni')
TARGET_SUBNET=$(echo "${TARGET_TASK}" | jq -r '.subnet')

if [[ -z "${TARGET_ENI}" || "${TARGET_ENI}" == "null" ]]; then
  echo "ERROR: Could not resolve ENI for task ${TARGET_TASK_ID}"
  echo "Task detail:"
  echo "${TARGET_TASK}" | jq '.'
  exit 1
fi

echo "Selected target broker:"
echo "  Task ID:  ${TARGET_TASK_ID}"
echo "  AZ:       ${TARGET_TASK_AZ}"
echo "  ENI:      ${TARGET_ENI}"
echo "  Subnet:   ${TARGET_SUBNET}"
echo ""

# --- Ensure CloudWatch log group exists ---
ensure_log_group "${LOG_GROUP}"

# --- Build and create the experiment template ---
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FIS_EXPERIMENT_ROLE}"
SUBNET_ARN="arn:aws:ec2:${AWS_REGION}:${ACCOUNT_ID}:subnet/${TARGET_SUBNET}"
LOG_GROUP_ARN="arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"

cat > /tmp/fis-broker-disconnect-template.json << EOF
{
  "description": "Disconnect broker ${TARGET_TASK_ID} (${PREFIX}) in ${TARGET_TASK_AZ} for ${DURATION}",
  "targets": {
    "target-subnet": {
      "resourceType": "aws:ec2:subnet",
      "resourceArns": ["${SUBNET_ARN}"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disconnect-broker": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "scope": "availability-zone",
        "duration": "${DURATION}"
      },
      "targets": {
        "Subnets": "target-subnet"
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
    "experiment_type": "broker-disconnect",
    "benchmark_prefix": "${PREFIX}",
    "target_task_id": "${TARGET_TASK_ID}",
    "target_eni": "${TARGET_ENI}",
    "target_az": "${TARGET_TASK_AZ}",
    "target_subnet": "${TARGET_SUBNET}",
    "duration": "${DURATION}",
    "environment": "dev",
    "managed_by": "chaos-tests",
    "repository": "camunda/camunda-deployment-references"
  }
}
EOF

# --- Delete existing template and create new one ---
delete_template_by_name "${TEMPLATE_NAME}"
create_template /tmp/fis-broker-disconnect-template.json

echo ""
echo "=== Experiment template created ==="
echo "Template ID: ${TEMPLATE_ID}"
echo "Name:        ${TEMPLATE_NAME}"
echo ""
echo "To run the experiment:"
echo "  ./experiments/broker-disconnect/broker-disconnect-run.sh --name ${TEMPLATE_NAME} --endpoint <ALB_DNS>"
echo "  # or"
echo "  ./experiments/broker-disconnect/broker-disconnect-run.sh --id ${TEMPLATE_ID} --endpoint <ALB_DNS>"
echo ""
echo "NOTE: This template targets the subnet ${TARGET_SUBNET} (${TARGET_TASK_AZ})."
echo "      If ECS reschedules the broker to a different subnet/AZ, recreate the template."

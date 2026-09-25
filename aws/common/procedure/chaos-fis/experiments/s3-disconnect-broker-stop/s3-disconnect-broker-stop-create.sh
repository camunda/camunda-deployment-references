#!/usr/bin/env bash
#
# s3-disconnect-broker-stop-create.sh
#
# Creates an FIS experiment template that combines two simultaneous faults:
#   1. Block S3 access from one broker's subnet (aws:network:disrupt-connectivity, scope=s3)
#   2. Stop a different broker task (aws:ecs:stop-task)
#
# Both actions run in parallel — the S3 disconnect begins and the broker stop
# fires at the same time. This simulates a compound failure: one broker loses
# S3 connectivity while another broker crashes and must be replaced.
#
# How it works:
#   1. Finds the ECS service for the given deployment prefix
#   2. Lists running tasks and picks TWO in different AZs
#   3. Broker A's subnet → S3 disconnect target
#   4. Broker B → ECS stop-task target (via cluster/service parameters)
#   5. Creates a single FIS template with both actions (parallel)
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Setup scripts have been run (including FIS-Experiment-Role with ECS permissions)
#   - Benchmark ECS service is running with at least 2 tasks
#
# Usage:
#   ./experiments/s3-disconnect-broker-stop/s3-disconnect-broker-stop-create.sh --prefix camunda --duration PT10M
#
# Options:
#   --prefix        Deployment prefix, var.prefix of the ECS reference architecture (required, e.g. camunda)
#   --duration      S3 disruption duration in ISO 8601 (default: PT5M)
#   --name          Experiment template name tag (default: s3-disconnect-broker-stop-<prefix>)
#   --cluster       ECS cluster name (default: camunda-cluster)
#   --log-group     CloudWatch log group (default: /fis/chaos-tests)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

# --- Defaults ---
AWS_REGION="${AWS_REGION:-eu-west-2}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"
ECS_CLUSTER="${ECS_CLUSTER:-camunda-cluster}"
DURATION="PT5M"
PREFIX=""
TEMPLATE_NAME=""
LOG_GROUP="${FIS_LOG_GROUP:-/fis/chaos-tests}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --prefix)        PREFIX="$2";        shift 2 ;;
    --duration)      DURATION="$2";      shift 2 ;;
    --name)          TEMPLATE_NAME="$2"; shift 2 ;;
    --cluster)       ECS_CLUSTER="$2";   shift 2 ;;
    --log-group)     LOG_GROUP="$2";     shift 2 ;;
    -h|--help)
      echo "Usage: $0 --prefix <PREFIX> [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --prefix        Deployment prefix (required, e.g. camunda)"
      echo "  --duration      S3 disruption duration in ISO 8601 (default: PT5M)"
      echo "  --name          Template name tag (default: s3-disconnect-broker-stop-<prefix>)"
      echo "  --cluster       ECS cluster name (default: camunda-cluster)"
      echo "  --log-group     CloudWatch log group for FIS logs (default: /fis/chaos-tests)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${PREFIX}" ]]; then
  echo "ERROR: --prefix is required."
  echo "Usage: $0 --prefix camunda [--duration PT5M]"
  exit 1
fi

if [[ -z "${TEMPLATE_NAME}" ]]; then
  TEMPLATE_NAME="s3-disconnect-broker-stop-${PREFIX}"
fi

echo "=== Creating S3 Disconnect + Broker Stop Combined Experiment ==="
echo "Deployment prefix: ${PREFIX}"
echo "ECS cluster:      ${ECS_CLUSTER}"
echo "S3 duration:      ${DURATION}"
echo "Template name:    ${TEMPLATE_NAME}"
echo "Region:           ${AWS_REGION}"
echo "Log group:        ${LOG_GROUP}"
echo ""

# --- Get account ID ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"

# --- Discover ECS service and tasks ---
discover_ecs_service "${PREFIX}"
list_running_tasks 2
describe_tasks_with_network

# --- Select two tasks in different AZs if possible ---
# Get unique AZs
AZ_LIST=$(echo "${TASKS_DETAIL}" | jq -r '[.[].az] | unique | .[]')
AZ_COUNT=$(echo "${AZ_LIST}" | wc -l)

if [[ "${AZ_COUNT}" -ge 2 ]]; then
  # Pick two AZs randomly
  SELECTED_AZS=$(echo "${AZ_LIST}" | shuf | head -2)
  AZ_A=$(echo "${SELECTED_AZS}" | head -1)
  AZ_B=$(echo "${SELECTED_AZS}" | tail -1)

  # Task A: S3 disconnect target (first task in AZ_A)
  S3_TASK=$(echo "${TASKS_DETAIL}" | jq -r --arg az "${AZ_A}" '[.[] | select(.az == $az)] | first')
  # Task B: broker stop target (first task in AZ_B)
  STOP_TASK=$(echo "${TASKS_DETAIL}" | jq -r --arg az "${AZ_B}" '[.[] | select(.az == $az)] | first')

  echo "Selected tasks from different AZs:"
else
  # All tasks in the same AZ — pick two different ones
  S3_TASK=$(echo "${TASKS_DETAIL}" | jq -r '.[0]')
  STOP_TASK=$(echo "${TASKS_DETAIL}" | jq -r '.[1]')

  echo "NOTE: All tasks are in the same AZ. Selecting two different tasks:"
fi

S3_TASK_ARN=$(echo "${S3_TASK}" | jq -r '.taskArn')
S3_TASK_ID=$(echo "${S3_TASK_ARN}" | rev | cut -d'/' -f1 | rev)
S3_TASK_AZ=$(echo "${S3_TASK}" | jq -r '.az')
S3_SUBNET=$(echo "${S3_TASK}" | jq -r '.subnet')
S3_ENI=$(echo "${S3_TASK}" | jq -r '.eni')

STOP_TASK_ARN=$(echo "${STOP_TASK}" | jq -r '.taskArn')
STOP_TASK_ID=$(echo "${STOP_TASK_ARN}" | rev | cut -d'/' -f1 | rev)
STOP_TASK_AZ=$(echo "${STOP_TASK}" | jq -r '.az')

if [[ -z "${S3_SUBNET}" || "${S3_SUBNET}" == "null" ]]; then
  echo "ERROR: Could not resolve subnet for S3 disconnect task ${S3_TASK_ID}"
  exit 1
fi

echo ""
echo "  Broker A (S3 disconnect):"
echo "    Task ID:  ${S3_TASK_ID}"
echo "    AZ:       ${S3_TASK_AZ}"
echo "    ENI:      ${S3_ENI}"
echo "    Subnet:   ${S3_SUBNET}"
echo ""
echo "  Broker B (stop):"
echo "    Task ID:  ${STOP_TASK_ID}"
echo "    AZ:       ${STOP_TASK_AZ}"
echo ""

# --- Ensure CloudWatch log group exists ---
ensure_log_group "${LOG_GROUP}"

# --- Build and create the experiment template ---
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FIS_EXPERIMENT_ROLE}"
SUBNET_ARN="arn:aws:ec2:${AWS_REGION}:${ACCOUNT_ID}:subnet/${S3_SUBNET}"
LOG_GROUP_ARN="arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"

# The stop-task target uses cluster/service parameters with COUNT(1) selection.
# FIS resolves targets at experiment start, then the stop-task action picks one
# random task from the service. We record the intended STOP_TASK_ID in tags for
# reference, but the actual stopped task is chosen by FIS at runtime.
cat > /tmp/fis-s3-disconnect-broker-stop-template.json << EOF
{
  "description": "S3 disconnect on ${S3_TASK_AZ} subnet + stop broker task in ${STOP_TASK_AZ} (${PREFIX}) — duration ${DURATION}",
  "targets": {
    "s3-disconnect-subnet": {
      "resourceType": "aws:ec2:subnet",
      "resourceArns": ["${SUBNET_ARN}"],
      "selectionMode": "ALL"
    },
    "stop-task-target": {
      "resourceType": "aws:ecs:task",
      "resourceArns": ["${STOP_TASK_ARN}"],
      "selectionMode": "COUNT(1)"
    }
  },
  "actions": {
    "disconnect-s3": {
      "actionId": "aws:network:disrupt-connectivity",
      "description": "Block S3 traffic from broker in ${S3_TASK_AZ}",
      "parameters": {
        "scope": "s3",
        "duration": "${DURATION}"
      },
      "targets": {
        "Subnets": "s3-disconnect-subnet"
      }
    },
    "stop-broker": {
      "actionId": "aws:ecs:stop-task",
      "description": "Stop broker task in ${STOP_TASK_AZ}",
      "targets": {
        "Tasks": "stop-task-target"
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
    "experiment_type": "s3-disconnect-broker-stop",
    "benchmark_prefix": "${PREFIX}",
    "s3_disconnect_task_id": "${S3_TASK_ID}",
    "s3_disconnect_az": "${S3_TASK_AZ}",
    "s3_disconnect_subnet": "${S3_SUBNET}",
    "stop_task_id": "${STOP_TASK_ID}",
    "stop_task_az": "${STOP_TASK_AZ}",
    "duration": "${DURATION}",
    "environment": "dev",
    "managed_by": "chaos-tests",
    "repository": "camunda/camunda-deployment-references"
  }
}
EOF

# --- Delete existing template and create new one ---
delete_template_by_name "${TEMPLATE_NAME}"
create_template /tmp/fis-s3-disconnect-broker-stop-template.json

echo ""
echo "=== Experiment template created ==="
echo "Template ID: ${TEMPLATE_ID}"
echo "Name:        ${TEMPLATE_NAME}"
echo ""
echo "Actions (run in parallel):"
echo "  1. disconnect-s3: Block S3 traffic from subnet ${S3_SUBNET} (${S3_TASK_AZ}) for ${DURATION}"
echo "  2. stop-broker:   Stop task ${STOP_TASK_ID} in ${STOP_TASK_AZ}"
echo ""
echo "To run the experiment:"
echo "  ./experiments/s3-disconnect-broker-stop/s3-disconnect-broker-stop-run.sh --name ${TEMPLATE_NAME} --endpoint <ALB_DNS> --prefix ${PREFIX}"
echo "  # or"
echo "  ./experiments/s3-disconnect-broker-stop/s3-disconnect-broker-stop-run.sh --id ${TEMPLATE_ID} --endpoint <ALB_DNS> --prefix ${PREFIX}"
echo ""
echo "NOTE: Both actions run simultaneously. The S3 disconnect lasts ${DURATION}."
echo "      The stop-broker action fires immediately; ECS will replace the stopped task."
echo "      If tasks are rescheduled to different subnets/AZs, recreate the template."

#!/usr/bin/env bash
#
# broker-stop-create.sh
#
# Creates an FIS experiment template that stops a single Camunda broker (ECS task)
# using the aws:ecs:stop-task action.
#
# How it works:
#   1. Finds the ECS service for the given benchmark prefix
#   2. Lists running tasks and picks one randomly (or in a specified AZ)
#   3. Creates an FIS experiment template using aws:ecs:stop-task,
#      targeting the selected task by ARN
#
# When the experiment runs, FIS stops the selected ECS task. The ECS service
# automatically launches a replacement, testing the cluster's ability to recover
# from a broker crash/restart — the most common real-world failure mode.
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Setup scripts have been run (including FIS-Experiment-Role with ECS permissions)
#   - Benchmark ECS service is running
#
# Usage:
#   ./experiments/broker-stop/broker-stop-create.sh --prefix benchmark1
#   ./experiments/broker-stop/broker-stop-create.sh --prefix benchmark1 --az eu-west-1b
#
# Options:
#   --prefix        Benchmark prefix to find ECS service (required, e.g., benchmark1)
#   --az            Target a broker in this AZ (default: random task)
#   --name          Experiment template name tag (default: broker-stop-<prefix>)
#   --cluster       ECS cluster name (default: camunda-cluster)
#   --log-group     CloudWatch log group (default: /fis/chaos-tests)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

# --- Defaults ---
AWS_REGION="${AWS_REGION:-eu-west-1}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"
ECS_CLUSTER="${ECS_CLUSTER:-camunda-cluster}"
PREFIX=""
TARGET_AZ=""
TEMPLATE_NAME=""
LOG_GROUP="${FIS_LOG_GROUP:-/fis/chaos-tests}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --prefix)        PREFIX="$2";        shift 2 ;;
    --az)            TARGET_AZ="$2";     shift 2 ;;
    --name)          TEMPLATE_NAME="$2"; shift 2 ;;
    --cluster)       ECS_CLUSTER="$2";   shift 2 ;;
    --log-group)     LOG_GROUP="$2";     shift 2 ;;
    -h|--help)
      echo "Usage: $0 --prefix <BENCHMARK_PREFIX> [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --prefix        Benchmark prefix (required, e.g., benchmark1)"
      echo "  --az            Target a broker in this AZ (default: random task)"
      echo "  --name          Template name tag (default: broker-stop-<prefix>)"
      echo "  --cluster       ECS cluster name (default: camunda-cluster)"
      echo "  --log-group     CloudWatch log group for FIS logs (default: /fis/chaos-tests)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${PREFIX}" ]]; then
  echo "ERROR: --prefix is required."
  echo "Usage: $0 --prefix benchmark1"
  exit 1
fi

if [[ -z "${TEMPLATE_NAME}" ]]; then
  TEMPLATE_NAME="broker-stop-${PREFIX}"
fi

echo "=== Creating Broker Stop Experiment Template ==="
echo "Benchmark prefix: ${PREFIX}"
echo "ECS cluster:      ${ECS_CLUSTER}"
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
describe_tasks_basic
select_task_by_az_or_random "${TARGET_AZ}"

echo "Selected target broker:"
echo "  Task ID:  ${TARGET_TASK_ID}"
echo "  AZ:       ${TARGET_TASK_AZ}"
echo ""

# --- Ensure CloudWatch log group exists ---
ensure_log_group "${LOG_GROUP}"

# --- Build and create the experiment template ---
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FIS_EXPERIMENT_ROLE}"
LOG_GROUP_ARN="arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"

cat > /tmp/fis-broker-stop-template.json << EOF
{
  "description": "Stop broker ${TARGET_TASK_ID} (${PREFIX}) in ${TARGET_TASK_AZ}",
  "targets": {
    "stop-task-target": {
      "resourceType": "aws:ecs:task",
      "resourceArns": ["${TARGET_TASK_ARN}"],
      "selectionMode": "COUNT(1)"
    }
  },
  "actions": {
    "stop-broker": {
      "actionId": "aws:ecs:stop-task",
      "description": "Stop broker task ${TARGET_TASK_ID} in ${TARGET_TASK_AZ}",
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
    "experiment_type": "broker-stop",
    "benchmark_prefix": "${PREFIX}",
    "target_task_id": "${TARGET_TASK_ID}",
    "target_az": "${TARGET_TASK_AZ}",
    "environment": "dev",
    "managed_by": "chaos-tests",
    "repository": "camunda/camunda-deployment-references"
  }
}
EOF

# --- Delete existing template and create new one ---
delete_template_by_name "${TEMPLATE_NAME}"
create_template /tmp/fis-broker-stop-template.json

echo ""
echo "=== Experiment template created ==="
echo "Template ID: ${TEMPLATE_ID}"
echo "Name:        ${TEMPLATE_NAME}"
echo ""
echo "To run the experiment:"
echo "  ./experiments/broker-stop/broker-stop-run.sh --name ${TEMPLATE_NAME} --endpoint <ALB_DNS> --prefix ${PREFIX}"
echo "  # or"
echo "  ./experiments/broker-stop/broker-stop-run.sh --id ${TEMPLATE_ID} --endpoint <ALB_DNS> --prefix ${PREFIX}"
echo ""
echo "NOTE: This template targets task ${TARGET_TASK_ID} in ${TARGET_TASK_AZ}."
echo "      If ECS reschedules the broker, recreate the template."

#!/usr/bin/env bash
#
# lib/common.sh — Shared functions for chaos test experiment scripts.
#
# Provides reusable functions for:
#   - ECS service/task discovery
#   - FIS template management (resolve, delete-existing, create)
#   - FIS experiment execution (start, poll, wait)
#   - Health checks (pre-check, post-check with recovery timing)
#   - Summary report helpers
#
# Usage:
#   Source this file from any experiment script:
#     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#     source "${SCRIPT_DIR}/../lib/common.sh"
#
# All functions expect the following globals to be set by the caller:
#   AWS_REGION        — AWS region (default: eu-west-1)
#   ECS_CLUSTER       — ECS cluster name
#
# Some functions require additional globals — see each function's doc comment.
#

# ============================================================
# ECS Discovery Functions
# ============================================================

# Find the ECS service matching a benchmark prefix.
#
# Globals: AWS_REGION, ECS_CLUSTER
# Arguments: $1 — benchmark prefix (e.g., "benchmark1")
# Outputs:   SERVICE_NAME (global) — the ECS service name
# Returns:   0 on success, exits 1 on failure
#
discover_ecs_service() {
  local prefix="$1"

  SERVICE_NAME=$(aws ecs list-services \
    --cluster "${ECS_CLUSTER}" \
    --query "serviceArns[?contains(@, '${prefix}-oc')]" \
    --output text \
    --region "${AWS_REGION}" | head -1 | xargs -I{} basename {})

  if [[ -z "${SERVICE_NAME}" || "${SERVICE_NAME}" == "None" ]]; then
    echo "ERROR: No ECS service found matching '${prefix}-oc' in cluster '${ECS_CLUSTER}'"
    echo ""
    echo "Available services:"
    aws ecs list-services \
      --cluster "${ECS_CLUSTER}" \
      --query "serviceArns[*]" \
      --output table \
      --region "${AWS_REGION}"
    exit 1
  fi
  echo "ECS service: ${SERVICE_NAME}"
}

# List running task ARNs for a service.
#
# Globals: AWS_REGION, ECS_CLUSTER, SERVICE_NAME
# Arguments: $1 — (optional) minimum task count required (default: 1)
# Outputs:   TASK_ARNS (global)  — JSON array of task ARNs
#            TASK_COUNT (global) — number of running tasks
# Returns:   0 on success, exits 1 on failure
#
list_running_tasks() {
  local min_tasks="${1:-1}"

  TASK_ARNS=$(aws ecs list-tasks \
    --cluster "${ECS_CLUSTER}" \
    --service-name "${SERVICE_NAME}" \
    --desired-status RUNNING \
    --query "taskArns[]" \
    --output json \
    --region "${AWS_REGION}")

  TASK_COUNT=$(echo "${TASK_ARNS}" | jq 'length')

  if [[ "${TASK_COUNT}" -lt "${min_tasks}" ]]; then
    if [[ "${min_tasks}" -eq 1 ]]; then
      echo "ERROR: No running tasks found for service '${SERVICE_NAME}'"
    else
      echo "ERROR: Need at least ${min_tasks} running tasks for this experiment, found ${TASK_COUNT}"
    fi
    exit 1
  fi

  echo "Running tasks: ${TASK_COUNT}"
}

# Describe tasks with basic info (taskArn, AZ, status).
# Use this when you don't need ENI/subnet details.
#
# Globals: AWS_REGION, ECS_CLUSTER, TASK_ARNS
# Outputs:  TASKS_DETAIL (global) — JSON array of {taskArn, az, lastStatus, startedAt}
#
describe_tasks_basic() {
  # shellcheck disable=SC2046 # word splitting is the point: --tasks takes one argument per task ARN
  TASKS_DETAIL=$(aws ecs describe-tasks \
    --cluster "${ECS_CLUSTER}" \
    --tasks $(echo "${TASK_ARNS}" | jq -r '.[]') \
    --query "tasks[*].{taskArn:taskArn,az:availabilityZone,lastStatus:lastStatus,startedAt:startedAt}" \
    --output json \
    --region "${AWS_REGION}")

  echo ""
  echo "Broker tasks:"
  echo "${TASKS_DETAIL}" | jq -r '.[] | "  [\(.taskArn | split("/") | last)] AZ: \(.az)  Status: \(.lastStatus)"'
  echo ""
}

# Describe tasks with ENI and subnet details.
# Use this when you need network-level targeting (broker-disconnect, s3-disconnect).
#
# Globals: AWS_REGION, ECS_CLUSTER, TASK_ARNS
# Outputs:  TASKS_DETAIL (global) — JSON array of {taskArn, az, eni, subnet}
#
describe_tasks_with_network() {
  local tasks_raw
  # shellcheck disable=SC2046 # word splitting is the point: --tasks takes one argument per task ARN
  tasks_raw=$(aws ecs describe-tasks \
    --cluster "${ECS_CLUSTER}" \
    --tasks $(echo "${TASK_ARNS}" | jq -r '.[]') \
    --output json \
    --region "${AWS_REGION}")

  TASKS_DETAIL=$(echo "${tasks_raw}" | jq '[.tasks[] | {
    taskArn: .taskArn,
    az: .availabilityZone,
    eni: ((.attachments // [] | map(select(.type == "ElasticNetworkInterface")) | .[0].details // [] | map(select(.name == "networkInterfaceId")) | .[0].value) // null),
    subnet: ((.attachments // [] | map(select(.type == "ElasticNetworkInterface")) | .[0].details // [] | map(select(.name == "subnetId")) | .[0].value) // null)
  }]')

  echo ""
  echo "Broker tasks:"
  echo "${TASKS_DETAIL}" | jq -r '.[] | "  [\(.taskArn | split("/") | last)] AZ: \(.az)  ENI: \(.eni)  Subnet: \(.subnet)"'
  echo ""
}

# Select a single task from TASKS_DETAIL by AZ or randomly.
#
# Globals: TASKS_DETAIL, TASK_COUNT
# Arguments: $1 — target AZ (empty string for random selection)
# Outputs:   TARGET_TASK (global)     — the selected task JSON object
#            TARGET_TASK_ARN (global) — task ARN
#            TARGET_TASK_ID (global)  — task ID (last segment of ARN)
#            TARGET_TASK_AZ (global)  — task AZ
#
select_task_by_az_or_random() {
  local target_az="$1"

  if [[ -n "${target_az}" ]]; then
    TARGET_TASK=$(echo "${TASKS_DETAIL}" | jq -r \
      --arg az "${target_az}" \
      '[.[] | select(.az == $az)] | first // empty')

    if [[ -z "${TARGET_TASK}" ]]; then
      echo "ERROR: No broker task found in AZ '${target_az}'"
      echo ""
      echo "Available AZs:"
      echo "${TASKS_DETAIL}" | jq -r '.[].az' | sort -u | sed 's/^/  /'
      exit 1
    fi
  else
    local random_index=$((RANDOM % TASK_COUNT))
    TARGET_TASK=$(echo "${TASKS_DETAIL}" | jq -r ".[${random_index}]")
    echo "Randomly selected broker index: ${random_index}"
  fi

  TARGET_TASK_ARN=$(echo "${TARGET_TASK}" | jq -r '.taskArn')
  # shellcheck disable=SC2034 # consumed by the sourcing script, see this function's Outputs header
  TARGET_TASK_ID=$(echo "${TARGET_TASK_ARN}" | rev | cut -d'/' -f1 | rev)
  # shellcheck disable=SC2034 # consumed by the sourcing script, see this function's Outputs header
  TARGET_TASK_AZ=$(echo "${TARGET_TASK}" | jq -r '.az')
}

# ============================================================
# FIS Template Functions
# ============================================================

# Ensure the CloudWatch log group exists.
#
# Globals: AWS_REGION
# Arguments: $1 — log group name
#
ensure_log_group() {
  local log_group="$1"
  echo "Ensuring CloudWatch log group '${log_group}' exists..."
  aws logs create-log-group \
    --log-group-name "${log_group}" \
    --region "${AWS_REGION}" 2>/dev/null || true
}

# Delete an existing FIS experiment template by name tag.
#
# Globals: AWS_REGION
# Arguments: $1 — template name tag
#
delete_template_by_name() {
  local template_name="$1"

  local existing_id
  existing_id=$(aws fis list-experiment-templates \
    --query "experimentTemplates[?tags.Name=='${template_name}'].id | [0]" \
    --output text \
    --region "${AWS_REGION}" 2>/dev/null) || true

  if [[ -n "${existing_id}" && "${existing_id}" != "None" ]]; then
    echo "Deleting existing template '${template_name}' (${existing_id})..."
    aws fis delete-experiment-template \
      --id "${existing_id}" \
      --region "${AWS_REGION}" > /dev/null
    echo "Deleted."
  fi
}

# Create an FIS experiment template from a JSON file.
#
# Globals: AWS_REGION
# Arguments: $1 — path to the template JSON file
# Outputs:   TEMPLATE_ID (global) — the created template ID
#
create_template() {
  local json_file="$1"

  echo "Creating experiment template..."
  local result
  result=$(aws fis create-experiment-template \
    --cli-input-json "file://${json_file}" \
    --region "${AWS_REGION}" \
    --output json)

  TEMPLATE_ID=$(echo "${result}" | jq -r '.experimentTemplate.id')
}

# ============================================================
# FIS Experiment Run Functions
# ============================================================

# Resolve a template ID from a name tag.
# If TEMPLATE_ID is already set, this is a no-op.
# If TEMPLATE_NAME is set and TEMPLATE_ID is empty, resolves by tag lookup.
#
# Globals: AWS_REGION, TEMPLATE_ID, TEMPLATE_NAME
# Outputs:  TEMPLATE_ID (global) — resolved template ID
# Returns:  exits 1 if neither ID nor name provided, or name not found
#
resolve_template() {
  if [[ -z "${TEMPLATE_ID}" && -n "${TEMPLATE_NAME}" ]]; then
    TEMPLATE_ID=$(aws fis list-experiment-templates \
      --query "experimentTemplates[?tags.Name=='${TEMPLATE_NAME}'].id | [0]" \
      --output text \
      --region "${AWS_REGION}")

    if [[ -z "${TEMPLATE_ID}" || "${TEMPLATE_ID}" == "None" ]]; then
      echo "ERROR: No experiment template found with name '${TEMPLATE_NAME}'"
      echo ""
      echo "Available templates:"
      aws fis list-experiment-templates \
        --query "experimentTemplates[*].[id,tags.Name,tags.experiment_type,tags.target_az]" \
        --output table \
        --region "${AWS_REGION}"
      exit 1
    fi
  fi

  if [[ -z "${TEMPLATE_ID}" ]]; then
    echo "ERROR: Must specify --name or --id"
    exit 1
  fi
}

# Get FIS experiment template details.
#
# Globals: AWS_REGION, TEMPLATE_ID
# Outputs:  TEMPLATE_INFO (global) — full JSON of the template
#
get_template_info() {
  # shellcheck disable=SC2034 # consumed by the sourcing script, see this function's Outputs header
  TEMPLATE_INFO=$(aws fis get-experiment-template \
    --id "${TEMPLATE_ID}" \
    --region "${AWS_REGION}" \
    --output json 2>/dev/null)
}

# Run the pre-experiment health check.
#
# Globals: EXPERIMENTS_DIR, ENDPOINT, PREFIX, ECS_CLUSTER, SKIP_PRE_CHECK
# Outputs:  PRE_CHECK_RESULT (global) — JSON result from health check
# Returns:  exits 1 if cluster is unhealthy (unless skipped)
#
run_pre_check() {
  echo "============================================="
  echo "  Phase 1: Pre-Experiment Health Check"
  echo "============================================="
  echo ""

  if [[ "${SKIP_PRE_CHECK}" == "true" ]]; then
    echo "Skipping pre-experiment health check (--skip-pre-check)"
    echo ""
    PRE_CHECK_RESULT='{"healthy": true, "details": "skipped"}'
    return 0
  fi

  local health_args=(--endpoint "${ENDPOINT}" --quiet)
  if [[ -n "${PREFIX}" ]]; then
    health_args+=(--prefix "${PREFIX}" --cluster "${ECS_CLUSTER}")
  fi

  local pre_rc=0
  PRE_CHECK_RESULT=$("${EXPERIMENTS_DIR}/verify-cluster-health.sh" \
    "${health_args[@]}") || pre_rc=1

  echo "${PRE_CHECK_RESULT}" | jq '.'
  echo ""

  if [[ ${pre_rc} -ne 0 ]]; then
    echo "ERROR: Cluster is not healthy before the experiment."
    echo "Fix the cluster before running chaos tests, or use --skip-pre-check."
    exit 1
  fi

  echo "Pre-check PASSED — cluster is healthy."
  echo ""
}

# Prompt for confirmation (unless AUTO_YES is set).
#
# Globals: AUTO_YES
# Arguments: $@ — lines to echo before the prompt
# Returns:   exits 0 if user declines
#
confirm_experiment() {
  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi

  for line in "$@"; do
    echo "$line"
  done
  echo ""
  read -p "Start the experiment? (y/N) " -n 1 -r
  echo ""

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
}

# Start an FIS experiment.
#
# Globals: AWS_REGION, TEMPLATE_ID
# Outputs:  EXPERIMENT_ID (global)    — experiment ID
#           EXPERIMENT_START (global) — ISO 8601 start timestamp
#
start_experiment() {
  echo "============================================="
  echo "  Phase 2: Running Experiment"
  echo "============================================="
  echo ""

  EXPERIMENT_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  echo "Starting experiment at ${EXPERIMENT_START}..."
  local result
  result=$(aws fis start-experiment \
    --experiment-template-id "${TEMPLATE_ID}" \
    --region "${AWS_REGION}" \
    --output json)

  EXPERIMENT_ID=$(echo "${result}" | jq -r '.experiment.id')
  local state
  state=$(echo "${result}" | jq -r '.experiment.state.status')

  echo "Experiment ID: ${EXPERIMENT_ID}"
  echo "State:         ${state}"
  echo ""
}

# Wait for an FIS experiment to reach a terminal state.
# Polls experiment status at a configurable interval.
#
# Globals: AWS_REGION, EXPERIMENT_ID
# Arguments: $1 — poll interval in seconds (default: 15)
# Outputs:   CURRENT_STATE (global)           — final experiment state
#            EXPERIMENT_END (global)           — ISO 8601 end timestamp
#            EXPERIMENT_STATE_REASON (global)  — state reason
#            EXPERIMENT_DETAIL (global)        — full experiment JSON (last poll)
#
wait_for_experiment() {
  local poll_interval="${1:-15}"

  echo "Waiting for experiment to complete..."
  echo ""

  while true; do
    EXPERIMENT_DETAIL=$(aws fis get-experiment \
      --id "${EXPERIMENT_ID}" \
      --region "${AWS_REGION}" \
      --output json 2>/dev/null)

    CURRENT_STATE=$(echo "${EXPERIMENT_DETAIL}" | jq -r '.experiment.state.status')

    echo "  $(date +%H:%M:%S) — State: ${CURRENT_STATE}"

    if [[ "${CURRENT_STATE}" == "completed" || "${CURRENT_STATE}" == "failed" || \
          "${CURRENT_STATE}" == "stopped" || "${CURRENT_STATE}" == "cancelled" ]]; then
      break
    fi

    sleep "${poll_interval}"
  done

  EXPERIMENT_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  EXPERIMENT_STATE_REASON=$(echo "${EXPERIMENT_DETAIL}" | jq -r '.experiment.state.reason // "none"')

  echo ""
  echo "Experiment finished at ${EXPERIMENT_END} with state: ${CURRENT_STATE}"
  if [[ "${EXPERIMENT_STATE_REASON}" != "none" && "${EXPERIMENT_STATE_REASON}" != "null" ]]; then
    echo "Reason: ${EXPERIMENT_STATE_REASON}"
  fi
  echo ""
}

# Wait for an FIS experiment showing per-action status.
# Use this for multi-action experiments.
#
# Globals: AWS_REGION, EXPERIMENT_ID
# Arguments: $1 — poll interval in seconds (default: 15)
# Outputs:   Same as wait_for_experiment
#
wait_for_experiment_with_actions() {
  local poll_interval="${1:-15}"

  echo "Waiting for experiment to complete..."
  echo ""

  while true; do
    EXPERIMENT_DETAIL=$(aws fis get-experiment \
      --id "${EXPERIMENT_ID}" \
      --region "${AWS_REGION}" \
      --output json 2>/dev/null)

    CURRENT_STATE=$(echo "${EXPERIMENT_DETAIL}" | jq -r '.experiment.state.status')

    local action_states
    action_states=$(echo "${EXPERIMENT_DETAIL}" | jq -r '
      [.experiment.actions | to_entries[] |
       "\(.key): \(.value.state.status // "pending")"] | join("  |  ")')

    echo "  $(date +%H:%M:%S) — Experiment: ${CURRENT_STATE}  |  ${action_states}"

    if [[ "${CURRENT_STATE}" == "completed" || "${CURRENT_STATE}" == "failed" || \
          "${CURRENT_STATE}" == "stopped" || "${CURRENT_STATE}" == "cancelled" ]]; then
      break
    fi

    sleep "${poll_interval}"
  done

  EXPERIMENT_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  EXPERIMENT_STATE_REASON=$(echo "${EXPERIMENT_DETAIL}" | jq -r '.experiment.state.reason // "none"')

  echo ""
  echo "Experiment finished at ${EXPERIMENT_END} with state: ${CURRENT_STATE}"
  if [[ "${EXPERIMENT_STATE_REASON}" != "none" && "${EXPERIMENT_STATE_REASON}" != "null" ]]; then
    echo "Reason: ${EXPERIMENT_STATE_REASON}"
  fi
  echo ""
}

# Run the post-experiment health check with recovery timing.
#
# Globals: EXPERIMENTS_DIR, ENDPOINT, PREFIX, ECS_CLUSTER, RECOVERY_WAIT
# Outputs:  POST_CHECK_RESULT (global)  — JSON result from health check
#           RECOVERY_STATUS (global)    — "PASSED" or "FAILED"
#           RECOVERY_DURATION (global)  — seconds elapsed during recovery check
#
run_post_check() {
  echo "============================================="
  echo "  Phase 3: Post-Experiment Recovery Check"
  echo "============================================="
  echo ""

  echo "Waiting for cluster to recover (timeout: ${RECOVERY_WAIT}s)..."
  echo ""

  local recovery_start recovery_end
  recovery_start=$(date +%s)

  local health_args=(--endpoint "${ENDPOINT}" --wait "${RECOVERY_WAIT}" --quiet)
  if [[ -n "${PREFIX}" ]]; then
    health_args+=(--prefix "${PREFIX}" --cluster "${ECS_CLUSTER}")
  fi

  local post_rc=0
  POST_CHECK_RESULT=$("${EXPERIMENTS_DIR}/verify-cluster-health.sh" \
    "${health_args[@]}") || post_rc=1

  recovery_end=$(date +%s)
  RECOVERY_DURATION=$((recovery_end - recovery_start))

  echo ""
  echo "Recovery check result:"
  echo "${POST_CHECK_RESULT}" | jq '.'
  echo ""

  if [[ ${post_rc} -eq 0 ]]; then
    echo "Post-check PASSED — cluster recovered in ~${RECOVERY_DURATION}s."
    RECOVERY_STATUS="PASSED"
  else
    echo "Post-check FAILED — cluster did NOT recover within ${RECOVERY_WAIT}s."
    RECOVERY_STATUS="FAILED"
  fi

  echo ""
}

# Print the summary report header.
#
print_summary_header() {
  echo "============================================="
  echo "  Experiment Summary"
  echo "============================================="
  echo ""
}

# Exit with the appropriate code based on experiment and recovery results.
#
# Globals: CURRENT_STATE, RECOVERY_STATUS
#
exit_with_result() {
  if [[ "${CURRENT_STATE}" != "completed" ]]; then
    echo ""
    echo "RESULT: FAIL (experiment state: ${CURRENT_STATE})"
    exit 1
  elif [[ "${RECOVERY_STATUS}" == "FAILED" ]]; then
    echo ""
    echo "RESULT: FAIL (cluster did not recover)"
    exit 1
  else
    echo ""
    echo "RESULT: PASS"
    exit 0
  fi
}

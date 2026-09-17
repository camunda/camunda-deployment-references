#!/usr/bin/env bash
#
# broker-stop-run.sh
#
# Runs a broker stop FIS experiment with pre- and post-experiment
# cluster health verification.
#
# This experiment stops a single Camunda broker (ECS task) using the FIS
# aws:ecs:stop-task action. The ECS service automatically launches a
# replacement, testing the cluster's ability to recover from a broker
# crash/restart — the most common real-world failure mode.
#
# Flow:
#   1. Pre-check: verify the cluster is healthy
#   2. Start the FIS experiment
#   3. Wait for the experiment to complete
#   4. Post-check: verify the cluster recovers within a timeout
#   5. Print a summary report
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Experiment template created (./experiments/broker-stop/broker-stop-create.sh)
#   - ALB endpoint reachable for health checks
#
# Usage:
#   ./experiments/broker-stop/broker-stop-run.sh --name broker-stop-benchmark1 --endpoint <ALB_DNS> --prefix benchmark1
#   ./experiments/broker-stop/broker-stop-run.sh --id EXT123 --endpoint <ALB_DNS> --prefix benchmark1 --recovery-wait 300
#
# Options:
#   --name           Template name (or use --id)
#   --id             Template ID (or use --name)
#   --endpoint       ALB DNS name for Camunda management API (required)
#   --prefix         Benchmark prefix for ECS service health check (optional)
#   --recovery-wait  Seconds to wait for post-experiment recovery (default: 900)
#   --cluster        ECS cluster name (default: camunda-cluster)
#   --skip-pre-check Skip the pre-experiment health check
#   --yes            Skip confirmation prompt
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "${EXPERIMENTS_DIR}/lib/common.sh"

AWS_REGION="${AWS_REGION:-eu-west-1}"
ECS_CLUSTER="${ECS_CLUSTER:-camunda-cluster}"
TEMPLATE_ID=""
TEMPLATE_NAME=""
PREFIX=""
ENDPOINT=""
RECOVERY_WAIT=900
SKIP_PRE_CHECK=false
AUTO_YES=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --id)             TEMPLATE_ID="$2";    shift 2 ;;
    --name)           TEMPLATE_NAME="$2";  shift 2 ;;
    --prefix)         PREFIX="$2";         shift 2 ;;
    --endpoint)       ENDPOINT="$2";       shift 2 ;;
    --recovery-wait)  RECOVERY_WAIT="$2";  shift 2 ;;
    --cluster)        ECS_CLUSTER="$2";    shift 2 ;;
    --skip-pre-check) SKIP_PRE_CHECK=true; shift ;;
    --yes)            AUTO_YES=true;       shift ;;
    -h|--help)
      echo "Usage: $0 --name <NAME> --endpoint <ALB_DNS> [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --name           Template name (or use --id)"
      echo "  --id             Template ID (or use --name)"
      echo "  --prefix         Benchmark prefix for ECS service health check (optional)"
      echo "  --endpoint       ALB DNS name for health checks (required)"
      echo "  --recovery-wait  Seconds to wait for recovery (default: 300)"
      echo "  --cluster        ECS cluster name (default: camunda-cluster)"
      echo "  --skip-pre-check Skip pre-experiment health check"
      echo "  --yes            Skip confirmation prompt"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${ENDPOINT}" ]]; then
  echo "ERROR: --endpoint is required for health verification."
  echo "Usage: $0 --name <NAME> --endpoint <ALB_DNS>"
  exit 1
fi

# --- Resolve template ---
resolve_template

# --- Get template details ---
get_template_info

DESCRIPTION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.description')
TARGET_AZ=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.target_az // "unknown"')
BENCHMARK_PREFIX=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.benchmark_prefix // "unknown"')
TARGET_TASK_ID=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.target_task_id // "unknown"')

echo "============================================="
echo "  Broker Stop Experiment"
echo "============================================="
echo ""
echo "Template ID:       ${TEMPLATE_ID}"
echo "Description:       ${DESCRIPTION}"
echo "Benchmark:         ${BENCHMARK_PREFIX}"
echo "Target broker:     ${TARGET_TASK_ID}"
echo "Target AZ:         ${TARGET_AZ}"
echo "Recovery wait:     ${RECOVERY_WAIT}s"
echo "Health endpoint:   ${ENDPOINT}:8080"
echo ""

# ========================================
# PHASE 1: Pre-experiment health check
# ========================================
run_pre_check

# ========================================
# Confirmation
# ========================================
confirm_experiment \
  "This experiment will STOP broker task ${TARGET_TASK_ID} in ${TARGET_AZ}." \
  "ECS will automatically launch a replacement task."

# ========================================
# PHASE 2: Run experiment
# ========================================
start_experiment

echo "Broker task is being stopped (ECS will launch a replacement)..."
echo ""

wait_for_experiment 10

# ========================================
# PHASE 3: Post-experiment health check
# ========================================
echo "Stopped task should be replaced by ECS."
run_post_check

# ========================================
# PHASE 4: Summary Report
# ========================================
print_summary_header

REPORT=$(jq -n \
  --arg experiment_type "broker-stop" \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --arg template_id "${TEMPLATE_ID}" \
  --arg template_name "${TEMPLATE_NAME}" \
  --arg benchmark "${BENCHMARK_PREFIX}" \
  --arg target_task "${TARGET_TASK_ID}" \
  --arg target_az "${TARGET_AZ}" \
  --arg experiment_state "${CURRENT_STATE}" \
  --arg experiment_reason "${EXPERIMENT_STATE_REASON}" \
  --arg experiment_start "${EXPERIMENT_START}" \
  --arg experiment_end "${EXPERIMENT_END}" \
  --argjson pre_check "${PRE_CHECK_RESULT}" \
  --argjson post_check "${POST_CHECK_RESULT}" \
  --arg recovery_status "${RECOVERY_STATUS}" \
  --argjson recovery_duration_seconds "${RECOVERY_DURATION}" \
  '{
    experiment_type: $experiment_type,
    experiment_id: $experiment_id,
    template_id: $template_id,
    template_name: $template_name,
    benchmark: $benchmark,
    target_task: $target_task,
    target_az: $target_az,
    experiment: {
      state: $experiment_state,
      reason: $experiment_reason,
      start: $experiment_start,
      end: $experiment_end
    },
    pre_check: $pre_check,
    post_check: $post_check,
    recovery: {
      status: $recovery_status,
      duration_seconds: $recovery_duration_seconds
    }
  }')

echo "${REPORT}" | jq '.'

exit_with_result

#!/usr/bin/env bash
#
# s3-disconnect-broker-stop-run.sh
#
# Runs a combined S3 disconnect + broker stop FIS experiment with
# pre- and post-experiment cluster health verification.
#
# This experiment runs two faults simultaneously:
#   1. Blocks S3 traffic from one broker's subnet (NACL-based)
#   2. Stops a different broker task (ECS StopTask)
#
# This tests how the Camunda cluster handles a compound failure — one broker
# loses S3 access while another broker crashes and must be replaced by ECS.
#
# Flow:
#   1. Pre-check: verify the cluster is healthy before the experiment
#   2. Start the FIS experiment (both actions run in parallel)
#   3. Wait for the experiment to complete
#   4. Post-check: verify the cluster recovers within a timeout
#   5. Print a summary report
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Experiment template created (s3-disconnect-broker-stop-create.sh)
#   - ALB endpoint reachable for health checks
#
# Usage:
#   ./experiments/s3-disconnect-broker-stop/s3-disconnect-broker-stop-run.sh --name s3-disconnect-broker-stop-camunda --endpoint <ALB_DNS> --prefix camunda
#
# Options:
#   --name           Template name (or use --id)
#   --id             Template ID (or use --name)
#   --endpoint       ALB DNS name for health checks (required)
#   --prefix         Deployment prefix for the ECS service health check (optional)
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

AWS_REGION="${AWS_REGION:-eu-west-2}"
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
      echo "Usage: $0 --name <NAME> --endpoint <ALB_DNS> --prefix <PREFIX> [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --name           Template name (or use --id)"
      echo "  --id             Template ID (or use --name)"
      echo "  --prefix         Deployment prefix for the ECS service health check (optional)"
      echo "  --endpoint       ALB DNS name for health checks (required)"
      echo "  --recovery-wait  Seconds to wait for recovery (default: 900)"
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
  echo "Usage: $0 --name <NAME> --endpoint <ALB_DNS> --prefix <PREFIX>"
  exit 1
fi

# --- Resolve template ---
resolve_template

# --- Get template details ---
get_template_info

DESCRIPTION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.description')
BENCHMARK_PREFIX=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.benchmark_prefix // "unknown"')
S3_DISCONNECT_AZ=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.s3_disconnect_az // "unknown"')
S3_DISCONNECT_TASK=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.s3_disconnect_task_id // "unknown"')
STOP_TASK_ID=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.stop_task_id // "unknown"')
STOP_TASK_AZ=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.stop_task_az // "unknown"')
DURATION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.duration // "unknown"')

echo "============================================="
echo "  S3 Disconnect + Broker Stop Experiment"
echo "============================================="
echo ""
echo "Template ID:         ${TEMPLATE_ID}"
echo "Description:         ${DESCRIPTION}"
echo "Benchmark:           ${BENCHMARK_PREFIX}"
echo ""
echo "  Action 1 — S3 disconnect:"
echo "    Broker (subnet):  ${S3_DISCONNECT_TASK}"
echo "    AZ:               ${S3_DISCONNECT_AZ}"
echo "    Duration:         ${DURATION}"
echo ""
echo "  Action 2 — Broker stop:"
echo "    Broker (task):    ${STOP_TASK_ID}"
echo "    AZ:               ${STOP_TASK_AZ}"
echo ""
echo "Recovery wait:       ${RECOVERY_WAIT}s"
echo "Health endpoint:     ${ENDPOINT}:8080"
echo ""

# ========================================
# PHASE 1: Pre-experiment health check
# ========================================
run_pre_check

# ========================================
# Confirmation
# ========================================
confirm_experiment \
  "This experiment will SIMULTANEOUSLY:" \
  "  1. Block S3 traffic from one broker's subnet for ${DURATION}" \
  "  2. Stop a different broker task (ECS will replace it)" \
  "BLAST RADIUS: fault 1 is subnet-scoped, so every task sharing that subnet" \
  "loses S3 access, not only the broker named above."

# ========================================
# PHASE 2: Run experiment
# ========================================
start_experiment

echo "Both actions are now running in parallel:"
echo "  - S3 traffic from the target subnet is blocked"
echo "  - A broker task is being stopped (ECS will launch a replacement)"
echo ""

# shellcheck disable=SC2119 # $1 is optional and documented with a default; "$@" would pass this script's CLI flags instead
wait_for_experiment_with_actions

# ========================================
# PHASE 3: Post-experiment health check
# ========================================
echo "S3 connectivity restored, stopped task should be replaced."
run_post_check

# ========================================
# PHASE 4: Summary Report
# ========================================
print_summary_header

REPORT=$(jq -n \
  --arg experiment_type "s3-disconnect-broker-stop" \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --arg template_id "${TEMPLATE_ID}" \
  --arg template_name "${TEMPLATE_NAME}" \
  --arg benchmark "${BENCHMARK_PREFIX}" \
  --arg s3_disconnect_task "${S3_DISCONNECT_TASK}" \
  --arg s3_disconnect_az "${S3_DISCONNECT_AZ}" \
  --arg stop_task "${STOP_TASK_ID}" \
  --arg stop_task_az "${STOP_TASK_AZ}" \
  --arg duration "${DURATION}" \
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
    actions: {
      s3_disconnect: {
        task: $s3_disconnect_task,
        az: $s3_disconnect_az,
        duration: $duration
      },
      broker_stop: {
        task: $stop_task,
        az: $stop_task_az
      }
    },
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

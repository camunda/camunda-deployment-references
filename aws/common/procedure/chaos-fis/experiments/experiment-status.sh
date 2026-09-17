#!/usr/bin/env bash
#
# experiment-status.sh
#
# Checks the status of an FIS experiment.
#
# Usage:
#   ./experiments/experiment-status.sh --id <EXPERIMENT_ID>
#   ./experiments/experiment-status.sh --id <EXPERIMENT_ID> --watch
#

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
EXPERIMENT_ID=""
WATCH=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --id)    EXPERIMENT_ID="$2"; shift 2 ;;
    --watch) WATCH=true;         shift ;;
    -h|--help)
      echo "Usage: $0 --id <EXPERIMENT_ID> [--watch]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${EXPERIMENT_ID}" ]]; then
  echo "ERROR: --id is required."
  echo ""
  echo "Recent experiments:"
  aws fis list-experiments \
    --query "experiments[*].[id,state.status,creationTime,tags.Name]" \
    --output table \
    --region "${AWS_REGION}" \
    --max-results 10
  exit 1
fi

get_status() {
  aws fis get-experiment \
    --id "${EXPERIMENT_ID}" \
    --region "${AWS_REGION}" \
    --output json 2>/dev/null | jq '{
      id: .experiment.id,
      state: .experiment.state.status,
      reason: .experiment.state.reason,
      start: .experiment.startTime,
      end: .experiment.endTime,
      actions: [.experiment.actions | to_entries[] | {
        name: .key,
        state: .value.state.status,
        reason: .value.state.reason
      }]
    }'
}

if [[ "${WATCH}" == "true" ]]; then
  echo "Watching experiment ${EXPERIMENT_ID} (Ctrl+C to stop)..."
  echo ""
  while true; do
    clear
    echo "=== FIS Experiment Status ($(date)) ==="
    echo ""
    get_status
    STATUS=$(aws fis get-experiment \
      --id "${EXPERIMENT_ID}" \
      --region "${AWS_REGION}" \
      --query "experiment.state.status" \
      --output text 2>/dev/null)
    if [[ "${STATUS}" == "completed" || "${STATUS}" == "failed" || "${STATUS}" == "stopped" || "${STATUS}" == "cancelled" ]]; then
      echo ""
      echo "Experiment finished with status: ${STATUS}"
      break
    fi
    sleep 10
  done
else
  echo "=== FIS Experiment Status ==="
  echo ""
  get_status
fi

#!/usr/bin/env bash
#
# experiment-stop.sh
#
# Stops a running FIS experiment.
#
# Usage:
#   ./experiments/experiment-stop.sh --id <EXPERIMENT_ID>
#

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
EXPERIMENT_ID=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --id) EXPERIMENT_ID="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --id <EXPERIMENT_ID>"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${EXPERIMENT_ID}" ]]; then
  echo "ERROR: --id is required."
  echo ""
  echo "Running experiments:"
  aws fis list-experiments \
    --query "experiments[?state.status=='running'].[id,state.status,creationTime,tags.Name]" \
    --output table \
    --region "${AWS_REGION}"
  exit 1
fi

echo "=== Stopping FIS Experiment ==="
echo "Experiment ID: ${EXPERIMENT_ID}"
echo ""

read -p "Stop the experiment? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

RESULT=$(aws fis stop-experiment \
  --id "${EXPERIMENT_ID}" \
  --region "${AWS_REGION}" \
  --output json)

STATE=$(echo "${RESULT}" | jq -r '.experiment.state.status')
echo ""
echo "Experiment state: ${STATE}"
echo ""
echo "Note: It may take a moment for FIS to restore network ACLs."
echo "Monitor with: ./experiments/experiment-status.sh --id ${EXPERIMENT_ID} --watch"

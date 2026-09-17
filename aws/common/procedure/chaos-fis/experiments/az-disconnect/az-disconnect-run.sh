#!/usr/bin/env bash
#
# az-disconnect-run.sh
#
# Starts an AZ disconnect FIS experiment from an existing template.
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Experiment template created (./experiments/az-disconnect/az-disconnect-create.sh)
#
# Usage:
#   ./experiments/az-disconnect/az-disconnect-run.sh --name az-disconnect-dev
#   ./experiments/az-disconnect/az-disconnect-run.sh --id EXT1234567890abcdef
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-eu-west-1}"
TEMPLATE_ID=""
TEMPLATE_NAME=""
AUTO_YES=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --id)   TEMPLATE_ID="$2";   shift 2 ;;
    --name) TEMPLATE_NAME="$2"; shift 2 ;;
    --yes)  AUTO_YES=true;      shift ;;
    -h|--help)
      echo "Usage: $0 --name <TEMPLATE_NAME> | --id <TEMPLATE_ID>"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Resolve template ID from name if needed
resolve_template

# Get template details
get_template_info

DESCRIPTION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.description')
TARGET_AZ=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.target_az // "unknown"')
DURATION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.actions[].parameters.duration // "unknown"')

echo "=== Starting FIS Experiment ==="
echo "Template ID:  ${TEMPLATE_ID}"
echo "Description:  ${DESCRIPTION}"
echo "Target AZ:    ${TARGET_AZ}"
echo "Duration:     ${DURATION}"
echo ""

confirm_experiment \
  "This experiment will disconnect AZ ${TARGET_AZ} for ${DURATION}." \
  "All services in this AZ will be affected."

echo ""
echo "Starting experiment..."
RESULT=$(aws fis start-experiment \
  --experiment-template-id "${TEMPLATE_ID}" \
  --region "${AWS_REGION}" \
  --output json)

EXPERIMENT_ID=$(echo "${RESULT}" | jq -r '.experiment.id')
STATE=$(echo "${RESULT}" | jq -r '.experiment.state.status')

echo ""
echo "=== Experiment started ==="
echo "Experiment ID: ${EXPERIMENT_ID}"
echo "State:         ${STATE}"
echo ""
echo "Monitor with:"
echo "  ./experiments/experiment-status.sh --id ${EXPERIMENT_ID}"
echo ""
echo "Stop early with:"
echo "  ./experiments/experiment-stop.sh --id ${EXPERIMENT_ID}"

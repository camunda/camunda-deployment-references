#!/usr/bin/env bash
#
# experiment-list.sh
#
# Lists all FIS experiment templates and recent experiments.
#
# Usage:
#   ./experiments/experiment-list.sh
#   ./experiments/experiment-list.sh --experiments
#

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
SHOW_EXPERIMENTS=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --experiments) SHOW_EXPERIMENTS=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--experiments]"
      echo ""
      echo "  --experiments  Also show recent experiment runs"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=== FIS Experiment Templates ==="
echo ""
aws fis list-experiment-templates \
  --query "experimentTemplates[*].{ID:id,Name:tags.Name,AZ:tags.target_az,Duration:tags.duration,Created:creationTime}" \
  --output table \
  --region "${AWS_REGION}"

if [[ "${SHOW_EXPERIMENTS}" == "true" ]]; then
  echo ""
  echo "=== Recent Experiment Runs ==="
  echo ""
  aws fis list-experiments \
    --query "experiments[*].{ID:id,Status:state.status,Template:experimentTemplateId,Started:creationTime,Name:tags.Name}" \
    --output table \
    --region "${AWS_REGION}" \
    --max-results 20
fi

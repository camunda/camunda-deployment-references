#!/bin/bash

# ------------------------------------------------------------------------------
#
# Description:
#   This file contains reusable utility functions for GitHub Actions workflows.
#
#   You can source this file in any workflow step to make the functions
#   available within that step.
#
# Usage:
#   source .github/scripts/gha-functions.sh
#   export_new_env_vars path/to/your/script.sh
# ------------------------------------------------------------------------------

export_new_env_vars() {
  local script_path="$1"

  env | sort > /tmp/env_before

  set -a
  # shellcheck source=/dev/null
  source "$script_path"
  set +a

  env | sort > /tmp/env_after

  comm -13 /tmp/env_before /tmp/env_after > /tmp/env_diff

  while IFS= read -r line; do
    echo "$line" >> "$GITHUB_ENV"
  done < /tmp/env_diff
}

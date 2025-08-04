#!/bin/bash

# ------------------------------------------------------------------------------
# Function: export_new_env_vars
#
# Description:
#   Sources a given shell script and detects any new environment variables
#   it exports, then appends those variables to the GITHUB_ENV file so they
#   persist across subsequent GitHub Actions steps.
#
# Parameters:
#   $1 - Path to the shell script to source
#
#
# Notes:
#   - Only variables newly introduced or modified by the script are captured.
#   - Requires the GITHUB_ENV environment variable to be available (set by GitHub Actions).
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

export_new_env_vars_to_file() {
  local script_path="$1"
  local output_file="${2:-${RUNNER_TEMP:-/tmp}/outputs_raw}"

  # Save current environment
  env | sort > /tmp/env_before

  # Source the script to load environment variables
  set -a
  # shellcheck source=/dev/null
  source "$script_path"
  set +a

  # Save environment after sourcing
  env | sort > /tmp/env_after

  # Find newly added variables
  comm -13 /tmp/env_before /tmp/env_after > /tmp/env_diff

  # Append new variables to output file
  while IFS= read -r line; do
    var_name="${line%%=*}"
    var_value="${line#*=}"
    echo "$var_name=$var_value" >> "$output_file"
  done < /tmp/env_diff
}

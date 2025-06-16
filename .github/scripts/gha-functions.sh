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


# scripts/functions.sh

say_hello() {
  echo "👋 Hello from a Bash function"
}

show_time() {
  echo "🕒 The current time is: $(date)"
}

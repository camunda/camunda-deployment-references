#!/bin/bash
set -euo pipefail

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

# ------------------------------------------------------------------------------
# Function: export_file_to_github_env
#
# Description:
#   Reads a file containing KEY=VALUE pairs and exports them to GITHUB_ENV.
#   Automatically masks sensitive values (containing SECRET or PASSWORD in the name)
#   to prevent them from appearing in logs.
#
# Parameters:
#   $1 - Path to the file containing KEY=VALUE pairs
#
# Usage:
#   source .github/scripts/gha-functions.sh
#   export_file_to_github_env "$RUNNER_TEMP/secrets_file"
# ------------------------------------------------------------------------------
export_file_to_github_env() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    echo "::error::File not found: $file_path"
    return 1
  fi

  while IFS= read -r line; do
    var_name="${line%%=*}"
    var_value="${line#*=}"

    # Mask sensitive values (secrets and passwords)
    if [[ "$var_name" == *SECRET* ]] || [[ "$var_name" == *PASSWORD* ]]; then
      echo "::add-mask::$var_value"
    fi

    echo "$line" >> "$GITHUB_ENV"
  done < "$file_path"
}

# ------------------------------------------------------------------------------
# Function: export_terraform_outputs
#
# Description:
#   Exports all Terraform outputs from the current workspace to GITHUB_OUTPUT.
#   Sensitive outputs are automatically masked using ::add-mask:: to prevent
#   them from appearing in GitHub Actions logs.
#   Each output is exported individually as key=value.
#   Additionally, exports 'all_terraform_outputs' as a compact JSON blob
#   for consumers that need the full Terraform output structure.
#
# Requirements:
#   - Must be run from within an initialized Terraform workspace
#   - Requires terraform, jq
#   - GITHUB_OUTPUT environment variable must be set (GitHub Actions)
#
# Usage:
#   source .github/scripts/gha-functions.sh
#   cd /path/to/terraform/module
#   export_terraform_outputs
# ------------------------------------------------------------------------------
export_terraform_outputs() {
  local TF_OUTPUT
  TF_OUTPUT=$(terraform output -json)

  # Mask sensitive outputs first
  echo "$TF_OUTPUT" | jq -r '
    to_entries[]
    | select(.value.sensitive == true)
    | .value.value
  ' | while IFS= read -r secret; do
    if [ -n "$secret" ]; then
      echo "::add-mask::$secret"
    fi
  done

  # Export all outputs individually to GITHUB_OUTPUT
  # Use heredoc delimiter for values that may contain special characters (maps, lists, multi-line)
  echo "$TF_OUTPUT" | jq -r '
    to_entries[] | "\(.key)<<TFEOF\n\(.value.value)\nTFEOF"
  ' >> "$GITHUB_OUTPUT"

  # Also export the full JSON for consumers needing the complete structure
  {
    echo "all_terraform_outputs<<TFEOF"
    echo "$TF_OUTPUT" | jq -c .
    echo "TFEOF"
  } >> "$GITHUB_OUTPUT"
}

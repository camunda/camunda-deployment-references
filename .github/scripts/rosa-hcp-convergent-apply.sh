#!/bin/bash
# ------------------------------------------------------------------------------
# Shared helper: convergent Terraform apply with retry for transient ROSA HCP
# compute-node provisioning timeouts.
#
# ROSA HCP compute-node provisioning is occasionally slow on the AWS side, which
# makes the rhcs provider's `wait_for_std_compute_nodes_complete` time out *after*
# the cluster itself has already been created. This is a transient infrastructure
# delay, not a configuration error.
#
# We retry such timeouts with a convergent apply: the cluster(s) already exist in
# the Terraform state, so a fresh plan + apply simply re-enters the wait on the
# existing cluster(s) (it does not recreate anything). Any error that is NOT a
# known compute-node provisioning timeout fails fast on the first attempt.
#
# This file only DEFINES the function; it intentionally does not enable `set -e`
# at file scope so it can be sourced into a step that runs with `set -uo pipefail`
# (the retry relies on inspecting non-zero exit codes itself).
#
# Usage:
#   source .github/scripts/rosa-hcp-convergent-apply.sh
#   rosa_hcp_convergent_apply <plan-file> [var-file] [max-attempts]
#
# Parameters:
#   $1 - Terraform plan file produced by the preceding `terraform plan` step
#        (e.g. rosa.plan or clusters.plan). Required.
#   $2 - Terraform var-file used when re-planning on retries. Default: terraform.tfvars
#   $3 - Maximum number of apply attempts. Default: 3
# ------------------------------------------------------------------------------

rosa_hcp_convergent_apply() {
  local plan_file="${1:?plan file is required}"
  local var_file="${2:-terraform.tfvars}"
  local max_attempts="${3:-3}"

  # Patterns emitted by the rhcs provider when the post-create node wait times out.
  local transient_pattern='std compute nodes|compute nodes completion|waiting for (std )?compute|context deadline exceeded|timeout while waiting'

  local attempt=1
  local rc
  while true; do
    if [ "${attempt}" -eq 1 ]; then
      # First attempt uses the plan produced by the previous step.
      terraform apply -no-color "${plan_file}" 2>&1 | tee apply.log
      rc="${PIPESTATUS[0]}"
    else
      # The saved plan is stale once the state has partially advanced, so we
      # re-plan against the current state before re-applying.
      terraform plan -no-color -var-file="${var_file}" -out "${plan_file}" 2>&1 | tee plan.log
      terraform apply -no-color "${plan_file}" 2>&1 | tee apply.log
      rc="${PIPESTATUS[0]}"
    fi

    if [ "${rc}" -eq 0 ]; then
      echo "Terraform apply succeeded on attempt ${attempt}."
      return 0
    fi

    if [ "${attempt}" -lt "${max_attempts}" ] && grep -Eiq "${transient_pattern}" apply.log; then
      echo "::warning::ROSA HCP compute-node provisioning timed out on attempt ${attempt}/${max_attempts} (rc=${rc})."
      echo "::warning::The cluster(s) exist in the Terraform state; re-planning and retrying the convergent apply."
      attempt=$((attempt + 1))
      sleep 60
      continue
    fi

    echo "::error::Terraform apply failed on attempt ${attempt} (rc=${rc}) and the error is not a known transient compute-node provisioning timeout. Failing."
    return "${rc}"
  done
}

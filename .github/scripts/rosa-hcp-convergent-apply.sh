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
# at file scope. The function works whether or not the caller has `errexit`
# enabled: it saves the caller's setting, disables `errexit` locally around the
# Terraform commands (whose non-zero exit codes it deliberately inspects for the
# retry), and restores the original setting on every return path.
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

  # Preserve the caller's errexit setting and disable it locally. The caller may
  # run with `set -e` (most steps in this repo use `set -euo pipefail`), but we
  # deliberately inspect non-zero Terraform exit codes to drive the retry, so we
  # must not let the first failing `terraform ... | tee` pipeline abort the step
  # before `rc` is captured. The original setting is restored on every return.
  local errexit_was_set=0
  case "$-" in
    *e*) errexit_was_set=1 ;;
  esac
  set +e

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
      # re-plan against the current state before re-applying. If the re-plan
      # itself fails, abort before applying a stale/empty plan file.
      terraform plan -no-color -var-file="${var_file}" -out "${plan_file}" 2>&1 | tee plan.log
      local plan_rc="${PIPESTATUS[0]}"
      if [ "${plan_rc}" -ne 0 ]; then
        echo "::error::Terraform re-plan failed on retry attempt ${attempt} (rc=${plan_rc}); aborting before apply to avoid using a stale plan."
        [ "${errexit_was_set}" -eq 1 ] && set -e
        return "${plan_rc}"
      fi
      terraform apply -no-color "${plan_file}" 2>&1 | tee apply.log
      rc="${PIPESTATUS[0]}"
    fi

    if [ "${rc}" -eq 0 ]; then
      echo "Terraform apply succeeded on attempt ${attempt}."
      [ "${errexit_was_set}" -eq 1 ] && set -e
      return 0
    fi

    if [ "${attempt}" -lt "${max_attempts}" ] && grep -Eiq "${transient_pattern}" apply.log; then
      echo "::warning::ROSA HCP compute-node provisioning timed out on attempt ${attempt}/${max_attempts} (rc=${rc})."
      echo "::warning::The cluster(s) exist in the Terraform state; re-planning and retrying the convergent apply."
      attempt=$((attempt + 1))
      sleep 60
      continue
    fi

    if grep -Eiq "${transient_pattern}" apply.log; then
      echo "::error::Terraform apply failed on attempt ${attempt} (rc=${rc}) with a transient ROSA HCP compute-node provisioning timeout, but the maximum number of attempts (${max_attempts}) was reached. Failing."
    else
      echo "::error::Terraform apply failed on attempt ${attempt} (rc=${rc}) and the error is not a known transient compute-node provisioning timeout. Failing."
    fi
    [ "${errexit_was_set}" -eq 1 ] && set -e
    return "${rc}"
  done
}

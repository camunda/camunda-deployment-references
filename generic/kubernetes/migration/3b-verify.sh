#!/bin/bash
# =============================================================================
# Phase 3b: Verify Data (OPTIONAL — NO DOWNTIME)
# =============================================================================
# Verifies that application data survived the migration by checking:
#   - Zeebe: process instances accessible via REST API
#   - Keycloak: users and clients in the camunda-platform realm
#   - WebModeler: projects (if WebModeler is deployed)
#
# This is complementary to Phase 4 (validate), which checks infrastructure
# health. This script checks that actual business data is accessible.
#
# Runs a Kubernetes Job inside the cluster to access Camunda services directly.
# Supports both OIDC and basic auth depending on Helm chart configuration.
#
# Usage:
#   ./3b-verify.sh                  # interactive
#   ./3b-verify.sh --yes            # non-interactive (CI)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Used by lib.sh after sourcing
CURRENT_SCRIPT="3b-verify.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
parse_common_args "$@"
load_state

check_env
require_phase 3 "Phase 3 (cutover)"

timer_start

section "Phase 3b: Verify Data (optional)"

echo "This will run a Kubernetes Job to verify that application data"
echo "is accessible after the migration."
echo ""

TESTS_DIR="${MIGRATION_DIR}/tests"

log_info "Running data verification job ..."
# Pass explicit varlist to prevent envsubst from clobbering the
# shell variables inside the embedded verification script.
# shellcheck disable=SC2016 # Intentional: literal ${NAMESPACE} for envsubst
run_job "${TESTS_DIR}/verify-test-data-job.yml" "verify-test-data" 600 '${NAMESPACE}'

echo ""
echo "--- Verification logs ---"
kubectl logs -n "${NAMESPACE}" "job/verify-test-data" 2>/dev/null || true

section "Phase 3b Complete ($(timer_elapsed))"
echo ""
echo "Next: ./4-validate.sh"

run_hooks "post-phase-3b"

#!/bin/bash

###############################################################################
# Print desired/running/pending counts for every ECS service of an            #
# ECS dual-region Fargate deployment, in both regions.                        #
#                                                                             #
# One call site replaces the eight near-identical `aws ecs describe-services` #
# invocations the guided-deployment commands used to carry twice over.        #
#                                                                             #
# Usage:                                                                      #
#   ./ecs_service_counts.sh <cluster_name> <region_0> <region_1> [aws_profile]#
#                                                                             #
# Exit status:                                                                #
#   0  every service has running == desired                                   #
#   1  at least one service has not converged yet (keep polling)              #
###############################################################################

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "usage: $0 <cluster_name> <region_0> <region_1> [aws_profile]" >&2
    exit 2
fi

CLUSTER_NAME="$1"
REGION_0="$2"
REGION_1="$3"
AWS_PROFILE_ARG=()
# An empty or literal "null" fourth argument means "no profile": terraform
# outputs a JSON null when aws_profile is unset, and the callers pass it through.
if [[ $# -eq 4 && -n "$4" && "$4" != "null" ]]; then
    AWS_PROFILE_ARG=(--profile "$4")
fi

converged=0

# describe_service <region> <cluster> <service> <expected_desired>
describe_service() {
    local region="$1" cluster="$2" service="$3" expected="$4"
    local counts desired running pending

    if ! counts=$(aws ecs describe-services \
        --cluster "${cluster}" \
        --services "${service}" \
        --region "${region}" \
        "${AWS_PROFILE_ARG[@]}" \
        --query 'services[0].[desiredCount,runningCount,pendingCount]' \
        --output text 2>/dev/null); then
        printf '%-14s %-46s ERROR (service not found or AWS call failed)\n' "${region}" "${service}"
        converged=1
        return
    fi

    read -r desired running pending <<<"${counts}"
    printf '%-14s %-46s desired=%s running=%s pending=%s' \
        "${region}" "${service}" "${desired}" "${running}" "${pending}"

    if [[ "${running}" == "${desired}" && "${running}" == "${expected}" ]]; then
        printf '  OK\n'
    else
        printf '  WAITING (expected %s)\n' "${expected}"
        converged=1
    fi
}

# Orchestration runs 4 tasks per region, connectors 1.
describe_service "${REGION_0}" "${CLUSTER_NAME}-r0-cluster" "${CLUSTER_NAME}-r0-oc-service" 4
describe_service "${REGION_1}" "${CLUSTER_NAME}-r1-cluster" "${CLUSTER_NAME}-r1-oc-service" 4
describe_service "${REGION_0}" "${CLUSTER_NAME}-r0-cluster" "${CLUSTER_NAME}-r0-oc-connectors-service" 1
describe_service "${REGION_1}" "${CLUSTER_NAME}-r1-cluster" "${CLUSTER_NAME}-r1-oc-connectors-service" 1

exit "${converged}"

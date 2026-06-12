#!/bin/bash

###############################################################################
# Test cross-region DNS resolution for ECS Dual-Region Fargate                #
#                                                                             #
# Verifies that Route 53 Resolver forwarding rules correctly resolve          #
# Cloud Map namespaces across regions via Transit Gateway.                    #
#                                                                             #
# Prerequisites:                                                              #
#   . ./export_environment_prerequisites.sh                                   #
###############################################################################

set -euo pipefail

: "${REGION_0:?REGION_0 must be set — source export_environment_prerequisites.sh first}"
: "${REGION_1:?REGION_1 must be set}"
: "${NLB_RAFT_ENDPOINT_0:?NLB_RAFT_ENDPOINT_0 must be set}"
: "${NLB_RAFT_ENDPOINT_1:?NLB_RAFT_ENDPOINT_1 must be set}"
: "${CLUSTER_0:?CLUSTER_0 must be set}"
: "${CLUSTER_1:?CLUSTER_1 must be set}"

PASS=0
FAIL=0

check() {
    local description=$1
    local result=$2

    if [ "${result}" = "0" ]; then
        echo "  ✅ ${description}"
        PASS=$((PASS + 1))
    else
        echo "  ❌ ${description}"
        FAIL=$((FAIL + 1))
    fi
}

###############################################################################
# Test 1: Internal NLB DNS resolution                                         #
###############################################################################

echo ""
echo "=== Test 1: Internal NLB DNS resolution ==="
echo ""

echo "Resolving NLB Raft endpoint for region 0: ${NLB_RAFT_ENDPOINT_0}"
if dig +short "${NLB_RAFT_ENDPOINT_0}" | grep -q '^[0-9]'; then
    check "Region 0 internal NLB (${NLB_RAFT_ENDPOINT_0}) resolves" 0
else
    check "Region 0 internal NLB (${NLB_RAFT_ENDPOINT_0}) resolves" 1
fi

echo "Resolving NLB Raft endpoint for region 1: ${NLB_RAFT_ENDPOINT_1}"
if dig +short "${NLB_RAFT_ENDPOINT_1}" | grep -q '^[0-9]'; then
    check "Region 1 internal NLB (${NLB_RAFT_ENDPOINT_1}) resolves" 0
else
    check "Region 1 internal NLB (${NLB_RAFT_ENDPOINT_1}) resolves" 1
fi

###############################################################################
# Test 2: Cloud Map namespace resolution via ECS Exec                         #
###############################################################################

echo ""
echo "=== Test 2: Cloud Map namespace resolution (via ECS Exec) ==="
echo ""
echo "Note: This test requires running ECS tasks with ECS Exec enabled."
echo "      If tasks are not running yet, this section will be skipped."
echo ""

resolve_from_task() {
    local region=$1
    local cluster=$2
    local target_hostname=$3
    local description=$4

    # Find a running task in the orchestration service
    local task_arn
    task_arn=$(aws ecs list-tasks \
        --region "${region}" \
        --cluster "${cluster}" \
        --service-name "${cluster%-cluster}-oc-orchestration-cluster" \
        --desired-status RUNNING \
        --query 'taskArns[0]' \
        --output text 2>/dev/null || echo "NONE")

    if [ "${task_arn}" = "NONE" ] || [ "${task_arn}" = "None" ]; then
        echo "  ⏭️  ${description} — skipped (no running tasks in ${cluster})"
        return
    fi

    if aws ecs execute-command \
        --region "${region}" \
        --cluster "${cluster}" \
        --task "${task_arn}" \
        --container "orchestration-cluster" \
        --interactive \
        --command "getent hosts ${target_hostname}" >/dev/null 2>&1; then
        check "${description}" 0
    else
        check "${description}" 1
    fi
}

resolve_from_task "${REGION_0}" "${CLUSTER_0}" "${NLB_RAFT_ENDPOINT_1}" \
    "Region 0 → Region 1 Raft NLB (cross-region)"
resolve_from_task "${REGION_1}" "${CLUSTER_1}" "${NLB_RAFT_ENDPOINT_0}" \
    "Region 1 → Region 0 Raft NLB (cross-region)"

###############################################################################
# Test 3: ALB health check                                                    #
###############################################################################

echo ""
echo "=== Test 3: ALB endpoint reachability ==="
echo ""

for region_label in 0 1; do
    alb_var="ALB_ENDPOINT_${region_label}"
    alb_dns="${!alb_var}"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${alb_dns}" 2>/dev/null || echo "000")
    if [ "${http_code}" != "000" ]; then
        check "Region ${region_label} ALB (${alb_dns}) reachable (HTTP ${http_code})" 0
    else
        check "Region ${region_label} ALB (${alb_dns}) reachable" 1
    fi
done

###############################################################################
# Summary                                                                     #
###############################################################################

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

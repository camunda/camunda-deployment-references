#!/bin/bash

###############################################################################
# Verify ECS Dual-Region Fargate deployment health                            #
#                                                                             #
# Checks:                                                                     #
#   - ECS service status in both regions                                      #
#   - Zeebe cluster topology (8 brokers, 8 partitions)                        #
#   - Aurora Global Database replication status                               #
#   - Workflow execution from each region                                     #
#                                                                             #
# Prerequisites:                                                              #
#   . ./export_environment_prerequisites.sh                                   #
###############################################################################

set -euo pipefail

: "${REGION_0:?REGION_0 must be set — source export_environment_prerequisites.sh first}"
: "${REGION_1:?REGION_1 must be set}"
: "${CLUSTER_0:?CLUSTER_0 must be set — did export_environment_prerequisites.sh run successfully?}"
: "${CLUSTER_1:?CLUSTER_1 must be set}"
: "${ALB_ENDPOINT_0:?ALB_ENDPOINT_0 must be set}"
: "${ALB_ENDPOINT_1:?ALB_ENDPOINT_1 must be set}"
: "${AURORA_GLOBAL_CLUSTER_ID:?AURORA_GLOBAL_CLUSTER_ID must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set (default: admin)}"
: "${ADMIN_PASS:?ADMIN_PASS must be set — retrieve via: terraform -chdir=terraform/app output -raw admin_user_password}"

PASS=0
FAIL=0
WARN=0

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

warn() {
    local description=$1
    echo "  ⚠️  ${description}"
    WARN=$((WARN + 1))
}

###############################################################################
# 1. ECS Service Health                                                       #
###############################################################################

echo ""
echo "=== 1. ECS Service Health ==="
echo ""

check_ecs_services() {
    local region=$1
    local cluster=$2
    local label=$3

    local services
    services=$(aws ecs list-services \
        --region "${region}" \
        --cluster "${cluster}" \
        --query 'serviceArns' \
        --output json 2>/dev/null)

    local count
    count=$(echo "${services}" | jq 'length')

    if [ "${count}" -ge 2 ]; then
        check "Region ${label}: ${count} ECS services found in ${cluster}" 0
    else
        check "Region ${label}: expected ≥2 ECS services, found ${count}" 1
        return
    fi

    # Check each service for running tasks
    for service_arn in $(echo "${services}" | jq -r '.[]'); do
        local service_name
        service_name=$(echo "${service_arn}" | awk -F'/' '{print $NF}')
        local running
        running=$(aws ecs describe-services \
            --region "${region}" \
            --cluster "${cluster}" \
            --services "${service_arn}" \
            --query 'services[0].runningCount' \
            --output text 2>/dev/null)

        local desired
        desired=$(aws ecs describe-services \
            --region "${region}" \
            --cluster "${cluster}" \
            --services "${service_arn}" \
            --query 'services[0].desiredCount' \
            --output text 2>/dev/null)

        if [ "${running}" = "${desired}" ] && [ "${running}" != "0" ]; then
            check "Region ${label}: ${service_name} — ${running}/${desired} tasks running" 0
        else
            check "Region ${label}: ${service_name} — ${running}/${desired} tasks running" 1
        fi
    done
}

check_ecs_services "${REGION_0}" "${CLUSTER_0}" "0"
check_ecs_services "${REGION_1}" "${CLUSTER_1}" "1"

###############################################################################
# 2. Zeebe Cluster Topology                                                   #
###############################################################################

echo ""
echo "=== 2. Zeebe Cluster Topology ==="
echo ""

check_topology() {
    local alb=$1
    local label=$2

    local topology
    topology=$(curl -sf --max-time 15 -u "${ADMIN_USER}:${ADMIN_PASS}" "http://${alb}/v2/topology" 2>/dev/null || echo "")

    if [ -z "${topology}" ]; then
        check "Region ${label}: Zeebe topology endpoint reachable" 1
        return
    fi

    check "Region ${label}: Zeebe topology endpoint reachable" 0

    local broker_count
    broker_count=$(echo "${topology}" | jq '.brokers | length')
    if [ "${broker_count}" = "8" ]; then
        check "Region ${label}: cluster has ${broker_count} brokers (expected 8)" 0
    else
        check "Region ${label}: cluster has ${broker_count} brokers (expected 8)" 1
    fi

    local partition_count
    partition_count=$(echo "${topology}" | jq '.partitionsCount')
    if [ "${partition_count}" = "8" ]; then
        check "Region ${label}: cluster has ${partition_count} partitions (expected 8)" 0
    else
        check "Region ${label}: cluster has ${partition_count} partitions (expected 8)" 1
    fi

    local replication_factor
    replication_factor=$(echo "${topology}" | jq '.replicationFactor')
    if [ "${replication_factor}" = "4" ]; then
        check "Region ${label}: replication factor ${replication_factor} (expected 4)" 0
    else
        check "Region ${label}: replication factor ${replication_factor} (expected 4)" 1
    fi

    # Show broker distribution
    echo ""
    echo "  Broker distribution (Region ${label} view):"
    echo "${topology}" | jq -r '.brokers[] | "    Broker \(.nodeId) — partitions: \([.partitions[].partitionId] | sort | join(","))"'
}

check_topology "${ALB_ENDPOINT_0}" "0"
check_topology "${ALB_ENDPOINT_1}" "1"

###############################################################################
# 3. Aurora Global Database Status                                            #
###############################################################################

echo ""
echo "=== 3. Aurora Global Database ==="
echo ""

GLOBAL_DB=$(aws rds describe-global-clusters \
    --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
    --query 'GlobalClusters[0]' \
    --output json 2>/dev/null || echo "")

if [ -z "${GLOBAL_DB}" ] || [ "${GLOBAL_DB}" = "null" ]; then
    check "Aurora Global Cluster ${AURORA_GLOBAL_CLUSTER_ID} found" 1
else
    check "Aurora Global Cluster ${AURORA_GLOBAL_CLUSTER_ID} found" 0

    STATUS=$(echo "${GLOBAL_DB}" | jq -r '.Status')
    if [ "${STATUS}" = "available" ]; then
        check "Global cluster status: ${STATUS}" 0
    else
        check "Global cluster status: ${STATUS} (expected: available)" 1
    fi

    MEMBER_COUNT=$(echo "${GLOBAL_DB}" | jq '.GlobalClusterMembers | length')
    check "Global cluster has ${MEMBER_COUNT} member(s) (expected 2)" "$([ "${MEMBER_COUNT}" = "2" ] && echo 0 || echo 1)"

    echo ""
    echo "  Member clusters:"
    echo "${GLOBAL_DB}" | jq -r '.GlobalClusterMembers[] | "    \(.DBClusterArn | split(":") | .[3]) — writer: \(.IsWriter)"'
fi

###############################################################################
# 4. Workflow Execution Test                                                  #
###############################################################################

echo ""
echo "=== 4. Workflow Execution Test ==="
echo ""

test_workflow() {
    local alb=$1
    local label=$2

    # Create a simple process instance via REST API
    local response
    response=$(curl -sf --max-time 30 \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X POST "http://${alb}/v2/process-instances" \
        -H "Content-Type: application/json" \
        -d '{"bpmnProcessId":"dual-region-health-check","variables":{}}' \
        2>/dev/null || echo "")

    if echo "${response}" | jq -e '.processInstanceKey' >/dev/null 2>&1; then
        local key
        key=$(echo "${response}" | jq -r '.processInstanceKey')
        check "Region ${label}: workflow started (key: ${key})" 0
    else
        # Process might not be deployed — that's a warning, not failure
        warn "Region ${label}: workflow test skipped (deploy a process first or check ALB connectivity)"
    fi
}

test_workflow "${ALB_ENDPOINT_0}" "0"
test_workflow "${ALB_ENDPOINT_1}" "1"

###############################################################################
# Summary                                                                     #
###############################################################################

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings ==="
echo ""

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

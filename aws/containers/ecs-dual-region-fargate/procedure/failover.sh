#!/bin/bash

###############################################################################
# Failover: ECS Dual-Region Fargate                                           #
#                                                                             #
# Performs a controlled failover from region 0 to region 1:                   #
#   1. Validates current state                                                #
#   2. Scales down region 0 ECS services                                      #
#   3. Promotes Aurora Global DB secondary (planned or unplanned)             #
#   4. Verifies region 1 quorum and connectivity                              #
#                                                                             #
# Usage:                                                                      #
#   ./failover.sh [--unplanned]                                               #
#                                                                             #
# Prerequisites:                                                              #
#   . ./export_environment_prerequisites.sh                                   #
###############################################################################

set -euo pipefail

: "${REGION_0:?REGION_0 must be set — source export_environment_prerequisites.sh first}"
: "${REGION_1:?REGION_1 must be set}"
: "${CLUSTER_0:?CLUSTER_0 must be set}"
: "${CLUSTER_1:?CLUSTER_1 must be set}"
: "${AURORA_GLOBAL_CLUSTER_ID:?AURORA_GLOBAL_CLUSTER_ID must be set}"
: "${ALB_ENDPOINT_1:?ALB_ENDPOINT_1 must be set}"

UNPLANNED=false
if [ "${1:-}" = "--unplanned" ]; then
    UNPLANNED=true
fi

###############################################################################
# Helper functions                                                            #
###############################################################################

log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

wait_aurora_available() {
    local cluster_id=$1
    local region=$2
    local max_wait=${3:-600}

    log "Waiting for Aurora cluster ${cluster_id} in ${region} to become available (timeout: ${max_wait}s)..."
    local elapsed=0
    while [ "${elapsed}" -lt "${max_wait}" ]; do
        local status
        status=$(aws rds describe-db-clusters \
            --region "${region}" \
            --db-cluster-identifier "${cluster_id}" \
            --query 'DBClusters[0].Status' \
            --output text 2>/dev/null || echo "unknown")

        if [ "${status}" = "available" ]; then
            log "Aurora cluster ${cluster_id} is available."
            return 0
        fi

        log "  Status: ${status} (${elapsed}s elapsed)"
        sleep 15
        elapsed=$((elapsed + 15))
    done

    err "Timed out waiting for Aurora cluster ${cluster_id} to become available."
    return 1
}

get_aurora_writer_region() {
    # shellcheck disable=SC2016  # JMESPath uses literal backticks, not shell command substitution
    aws rds describe-global-clusters \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn' \
        --output text 2>/dev/null | awk -F':' '{print $4}'
}

get_secondary_cluster_arn() {
    # shellcheck disable=SC2016  # JMESPath uses literal backticks, not shell command substitution
    aws rds describe-global-clusters \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`false`].DBClusterArn' \
        --output text 2>/dev/null
}

###############################################################################
# Step 1: Validate current state                                              #
###############################################################################

log "=== Step 1: Validate current state ==="

WRITER_REGION=$(get_aurora_writer_region)
log "Aurora writer is currently in: ${WRITER_REGION}"

if [ "${WRITER_REGION}" != "${REGION_0}" ]; then
    err "Aurora writer is not in region 0 (${REGION_0}). Current writer: ${WRITER_REGION}."
    err "Failover script expects writer in region 0. Aborting."
    exit 1
fi

log "Current state validated: writer in ${REGION_0}, ready to failover to ${REGION_1}."

###############################################################################
# Step 2: Scale down region 0 ECS services                                    #
###############################################################################

log ""
log "=== Step 2: Scale down region 0 ECS services ==="

SERVICES_0=$(aws ecs list-services \
    --region "${REGION_0}" \
    --cluster "${CLUSTER_0}" \
    --query 'serviceArns[]' \
    --output text 2>/dev/null)

for service_arn in ${SERVICES_0}; do
    service_name=$(echo "${service_arn}" | awk -F'/' '{print $NF}')
    log "Scaling down ${service_name} to 0 tasks..."
    aws ecs update-service \
        --region "${REGION_0}" \
        --cluster "${CLUSTER_0}" \
        --service "${service_arn}" \
        --desired-count 0 \
        --no-cli-pager >/dev/null
done

log "Waiting for region 0 tasks to drain (30s grace)..."
sleep 30

###############################################################################
# Step 3: Aurora Global DB failover                                           #
###############################################################################

log ""
log "=== Step 3: Aurora Global DB failover ==="

SECONDARY_ARN=$(get_secondary_cluster_arn)
SECONDARY_CLUSTER_ID=$(echo "${SECONDARY_ARN}" | awk -F':' '{print $7}')

if [ "${UNPLANNED}" = "true" ]; then
    log "UNPLANNED failover: detaching secondary cluster ${SECONDARY_CLUSTER_ID} and promoting..."

    aws rds remove-from-global-cluster \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --db-cluster-identifier "${SECONDARY_ARN}" \
        --no-cli-pager

    log "Secondary cluster detached. Waiting for promotion..."
    wait_aurora_available "${SECONDARY_CLUSTER_ID}" "${REGION_1}"
else
    log "PLANNED failover: switching writer to ${REGION_1}..."

    aws rds failover-global-cluster \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --target-db-cluster-identifier "${SECONDARY_ARN}" \
        --no-cli-pager

    log "Planned failover initiated. Waiting for completion..."
    sleep 15

    # Wait for both clusters to stabilize
    # shellcheck disable=SC2016  # JMESPath uses literal backticks, not shell command substitution
    PRIMARY_CLUSTER_ID=$(aws rds describe-global-clusters \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn' \
        --output text 2>/dev/null | awk -F':' '{print $7}')

    wait_aurora_available "${PRIMARY_CLUSTER_ID}" "${REGION_1}"
fi

# Verify writer moved
NEW_WRITER_REGION=$(get_aurora_writer_region)
if [ "${NEW_WRITER_REGION}" = "${REGION_1}" ]; then
    log "Aurora writer successfully moved to ${REGION_1}."
elif [ "${UNPLANNED}" = "true" ]; then
    log "Unplanned failover: secondary promoted independently (Global DB relationship removed)."
else
    err "Aurora writer did not move to ${REGION_1}. Current writer: ${NEW_WRITER_REGION}"
    exit 1
fi

###############################################################################
# Step 4: Verify region 1                                                     #
###############################################################################

log ""
log "=== Step 4: Verify region 1 health ==="

log "Waiting 60s for Zeebe brokers to detect topology change..."
sleep 60

TOPOLOGY=$(curl -sf --max-time 15 "http://${ALB_ENDPOINT_1}/v2/topology" 2>/dev/null || echo "")

if [ -z "${TOPOLOGY}" ]; then
    err "Cannot reach Zeebe topology endpoint at ${ALB_ENDPOINT_1}"
    err "Brokers may still be stabilizing. Run verify_dual_region.sh to check later."
    exit 1
fi

BROKER_COUNT=$(echo "${TOPOLOGY}" | jq '.brokers | length')
log "Zeebe cluster reports ${BROKER_COUNT} broker(s) via region 1."

if [ "${BROKER_COUNT}" -ge 4 ]; then
    log "Region 1 has sufficient brokers for quorum."
else
    err "Region 1 has only ${BROKER_COUNT} brokers — quorum may be lost."
    err "Check ECS tasks and CloudWatch logs."
    exit 1
fi

###############################################################################
# Summary                                                                     #
###############################################################################

log ""
log "=== Failover Complete ==="
log ""
log "Aurora writer:  ${REGION_1}"
log "Region 0:       scaled down (0 tasks)"
log "Region 1:       active (${BROKER_COUNT} brokers)"
if [ "${UNPLANNED}" = "true" ]; then
    log "Mode:           UNPLANNED (Global DB relationship removed)"
    log ""
    log "⚠️  To failback, you must re-add region 0 as a secondary cluster."
else
    log "Mode:           PLANNED (Global DB intact)"
fi
log ""
log "Next steps:"
log "  1. Verify workflow execution: curl http://${ALB_ENDPOINT_1}/v2/topology"
log "  2. Run verification: ./verify_dual_region.sh"
log "  3. To restore: ./failback.sh"

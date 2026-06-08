#!/bin/bash

###############################################################################
# Failback: ECS Dual-Region Fargate                                           #
#                                                                             #
# Restores balanced dual-region operation after a failover:                   #
#   1. Validates current state (writer in region 1, region 0 recovered)       #
#   2. Re-adds region 0 as Global DB secondary (if unplanned failover)        #
#   3. Scales up region 0 ECS services                                        #
#   4. Waits for Raft quorum across both regions                              #
#   5. Optionally switches Aurora writer back to region 0                     #
#                                                                             #
# Usage:                                                                      #
#   ./failback.sh [--switch-writer]                                           #
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
: "${ALB_ENDPOINT_0:?ALB_ENDPOINT_0 must be set}"
: "${ALB_ENDPOINT_1:?ALB_ENDPOINT_1 must be set}"

SWITCH_WRITER=false
if [ "${1:-}" = "--switch-writer" ]; then
    SWITCH_WRITER=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

get_global_cluster_members() {
    aws rds describe-global-clusters \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --query 'GlobalClusters[0].GlobalClusterMembers' \
        --output json 2>/dev/null || echo "[]"
}

###############################################################################
# Step 1: Validate current state                                              #
###############################################################################

log "=== Step 1: Validate current state ==="

# Check Global DB exists and get member count
MEMBERS=$(get_global_cluster_members)
MEMBER_COUNT=$(echo "${MEMBERS}" | jq 'length')

if [ "${MEMBER_COUNT}" = "0" ]; then
    err "Aurora Global Cluster ${AURORA_GLOBAL_CLUSTER_ID} not found or has no members."
    exit 1
fi

WRITER_ARN=$(echo "${MEMBERS}" | jq -r '.[] | select(.IsWriter == true) | .DBClusterArn')
WRITER_REGION=$(echo "${WRITER_ARN}" | awk -F':' '{print $4}')
log "Aurora writer is in: ${WRITER_REGION}"

if [ "${WRITER_REGION}" = "${REGION_0}" ] && [ "${SWITCH_WRITER}" = "false" ]; then
    log "Writer is already in region 0. Nothing to failback."
    log "If you want to verify dual-region health, run: ./verify_dual_region.sh"
    exit 0
fi

###############################################################################
# Step 2: Re-add region 0 as secondary (if needed)                            #
###############################################################################

log ""
log "=== Step 2: Ensure region 0 is a Global DB member ==="

if [ "${MEMBER_COUNT}" = "1" ]; then
    log "Global DB has only 1 member — re-adding region 0 as secondary..."

    # Find region 0's cluster identifier from Terraform output
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TF_DIR="${TF_DIR:-${SCRIPT_DIR}/../terraform/clusters}"
    REGION_0_CLUSTER_ARN=$(terraform -chdir="${TF_DIR}" output -json | \
        jq -r '.aurora_primary_endpoint.value' | \
        sed 's/\..*$//' || echo "")

    # Look up the actual cluster ARN in region 0
    REGION_0_DB_CLUSTERS=$(aws rds describe-db-clusters \
        --region "${REGION_0}" \
        --query "DBClusters[?contains(DBClusterIdentifier, '${CLUSTER_0%-cluster}')].DBClusterArn" \
        --output text 2>/dev/null || echo "")

    if [ -z "${REGION_0_DB_CLUSTERS}" ]; then
        err "Cannot find Aurora cluster in ${REGION_0} to re-add as secondary."
        err "Manual intervention required: aws rds create-db-cluster --global-cluster-identifier ${AURORA_GLOBAL_CLUSTER_ID} ..."
        exit 1
    fi

    REGION_0_CLUSTER_ARN="${REGION_0_DB_CLUSTERS}"
    log "Found region 0 cluster: ${REGION_0_CLUSTER_ARN}"

    # Re-add as secondary — requires the cluster to exist but be standalone
    # After unplanned failover, the region 0 cluster may need to be recreated
    # via terraform apply first
    log "⚠️  If region 0 cluster was destroyed, run 'terraform apply' first to recreate it."
    log "Then re-run this script."

    # For a cluster that still exists, we can try to add it back
    aws rds create-db-cluster \
        --region "${REGION_0}" \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --db-cluster-identifier "$(echo "${REGION_0_CLUSTER_ARN}" | awk -F':' '{print $7}')" \
        --engine aurora-postgresql \
        --no-cli-pager 2>/dev/null || {
            err "Failed to re-add region 0 cluster. It may need to be recreated via Terraform."
            err "Run: terraform -chdir=${TF_DIR} apply"
            exit 1
        }

    log "Waiting for region 0 cluster to sync..."
    wait_aurora_available "$(echo "${REGION_0_CLUSTER_ARN}" | awk -F':' '{print $7}')" "${REGION_0}" 900
else
    log "Global DB has ${MEMBER_COUNT} members — region 0 is already part of the cluster."
fi

###############################################################################
# Step 3: Scale up region 0 ECS services                                      #
###############################################################################

log ""
log "=== Step 3: Scale up region 0 ECS services ==="

SERVICES_0=$(aws ecs list-services \
    --region "${REGION_0}" \
    --cluster "${CLUSTER_0}" \
    --query 'serviceArns[]' \
    --output text 2>/dev/null)

for service_arn in ${SERVICES_0}; do
    service_name=$(echo "${service_arn}" | awk -F'/' '{print $NF}')

    # Determine desired count based on service type
    if echo "${service_name}" | grep -q "orchestration"; then
        desired=4
    else
        desired=1
    fi

    log "Scaling ${service_name} to ${desired} tasks..."
    aws ecs update-service \
        --region "${REGION_0}" \
        --cluster "${CLUSTER_0}" \
        --service "${service_arn}" \
        --desired-count "${desired}" \
        --no-cli-pager >/dev/null
done

###############################################################################
# Step 4: Wait for Raft quorum                                                #
###############################################################################

log ""
log "=== Step 4: Wait for 8-broker Raft quorum ==="

MAX_WAIT=600
ELAPSED=0
while [ "${ELAPSED}" -lt "${MAX_WAIT}" ]; do
    TOPOLOGY=$(curl -sf --max-time 15 "http://${ALB_ENDPOINT_1}/v2/topology" 2>/dev/null || echo "")

    if [ -n "${TOPOLOGY}" ]; then
        BROKER_COUNT=$(echo "${TOPOLOGY}" | jq '.brokers | length')
        if [ "${BROKER_COUNT}" = "8" ]; then
            log "All 8 brokers have joined the cluster."
            break
        fi
        log "  ${BROKER_COUNT}/8 brokers online (${ELAPSED}s elapsed)"
    else
        log "  Topology endpoint not reachable yet (${ELAPSED}s elapsed)"
    fi

    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ "${ELAPSED}" -ge "${MAX_WAIT}" ]; then
    err "Timed out waiting for 8 brokers. Run verify_dual_region.sh to check status."
    exit 1
fi

###############################################################################
# Step 5: Optionally switch writer back to region 0                           #
###############################################################################

if [ "${SWITCH_WRITER}" = "true" ]; then
    log ""
    log "=== Step 5: Switch Aurora writer back to region 0 ==="

    REGION_0_MEMBER_ARN=$(get_global_cluster_members | \
        jq -r --arg r "${REGION_0}" '.[] | select(.DBClusterArn | contains($r)) | .DBClusterArn')

    if [ -z "${REGION_0_MEMBER_ARN}" ]; then
        err "Cannot find region 0 member in Global DB."
        exit 1
    fi

    log "Initiating planned failover to region 0..."
    aws rds failover-global-cluster \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --target-db-cluster-identifier "${REGION_0_MEMBER_ARN}" \
        --no-cli-pager

    sleep 15
    REGION_0_CLUSTER_ID=$(echo "${REGION_0_MEMBER_ARN}" | awk -F':' '{print $7}')
    wait_aurora_available "${REGION_0_CLUSTER_ID}" "${REGION_0}"

    log "Aurora writer moved back to ${REGION_0}."
else
    log ""
    log "Skipping writer switch (pass --switch-writer to move writer back to region 0)."
fi

###############################################################################
# Summary                                                                     #
###############################################################################

# shellcheck disable=SC2016  # JMESPath uses literal backticks, not shell command substitution
FINAL_WRITER=$(aws rds describe-global-clusters \
    --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
    --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn' \
    --output text 2>/dev/null | awk -F':' '{print $4}')

log ""
log "=== Failback Complete ==="
log ""
log "Aurora writer:  ${FINAL_WRITER}"
log "Region 0:       active (scaled up)"
log "Region 1:       active"
log "Brokers:        8 (balanced across regions)"
log ""
log "Next steps:"
log "  1. Run verification: ./verify_dual_region.sh"
log "  2. Monitor CloudWatch logs for any Raft rebalancing issues"

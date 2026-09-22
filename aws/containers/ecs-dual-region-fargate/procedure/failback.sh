#!/usr/bin/env bash

###############################################################################
# Failback: ECS Dual-Region Fargate                                           #
#                                                                             #
# Restores balanced dual-region operation after ./failover.sh:                 #
#   1. Prints the topology before the change                                  #
#   2. Ensures the recovered region is an Aurora Global DB member             #
#   3. Scales the recovered region's ECS services back up                     #
#   4. Waits for its brokers to rejoin cluster membership                     #
#   5. Re-adds the zone via POST /actuator/cluster/zones/{zoneId}             #
#   6. Polls the change to COMPLETED and verifies partitions are hosted       #
#   7. Optionally switches the Aurora writer back                             #
#                                                                             #
# Why step 5 is not optional                                                  #
#   Failover force-removed the zone, which also dropped it from the persisted  #
#   partition distribution. Restarted brokers rejoin cluster membership but,   #
#   as the management API guide puts it, "do not host partitions until you     #
#   add the zone through the Zones API". Waiting for eight brokers in          #
#   /v2/topology therefore proves nothing on its own — without this step the   #
#   four restored brokers sit idle with zero replicas.                        #
#                                                                             #
# Usage:                                                                      #
#   ./failback.sh [--failed-region 0|1] [--switch-writer] [--dry-run]         #
#                [--replicas N] [--priority N] [--brokers N]                  #
#                                                                             #
# Defaults mirror terraform/app/locals.tf:                                    #
#   --replicas 2   (replication_factor / 2)                                   #
#   --brokers  4   (brokers_per_region)                                       #
#   --priority     1000 for region 0, 500 for region 1                        #
#                                                                             #
# Prerequisites:                                                              #
#   . ./export_environment_prerequisites.sh                                    #
#   session-manager-plugin (brew install --cask session-manager-plugin)       #
###############################################################################

set -euo pipefail

: "${REGION_0:?REGION_0 must be set — source export_environment_prerequisites.sh first}"
: "${REGION_1:?REGION_1 must be set}"
: "${CLUSTER_0:?CLUSTER_0 must be set}"
: "${CLUSTER_1:?CLUSTER_1 must be set}"
: "${AURORA_GLOBAL_CLUSTER_ID:?AURORA_GLOBAL_CLUSTER_ID must be set}"
: "${ALB_ENDPOINT_0:?ALB_ENDPOINT_0 must be set}"
: "${ALB_ENDPOINT_1:?ALB_ENDPOINT_1 must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set (default: admin)}"
: "${ADMIN_PASS:?ADMIN_PASS must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=SCRIPTDIR/zeebe_management_api.sh
. "${SCRIPT_DIR}/zeebe_management_api.sh"

###############################################################################
# Argument parsing                                                            #
###############################################################################

FAILED_REGION="0"
SWITCH_WRITER=false
DRY_RUN=false
ZONE_REPLICAS=2
ZONE_BROKERS=4
ZONE_PRIORITY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --failed-region) FAILED_REGION="$2"; shift 2 ;;
    --switch-writer) SWITCH_WRITER=true; shift ;;
    --dry-run)       DRY_RUN=true; shift ;;
    --replicas)      ZONE_REPLICAS="$2"; shift 2 ;;
    --brokers)       ZONE_BROKERS="$2"; shift 2 ;;
    --priority)      ZONE_PRIORITY="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ "$FAILED_REGION" != "0" && "$FAILED_REGION" != "1" ]]; then
  echo "ERROR: --failed-region must be 0 or 1"
  exit 1
fi

# Zone names are the AWS region names (terraform/app/locals.tf).
if [[ "$FAILED_REGION" == "0" ]]; then
  RECOVERED_ZONE="$REGION_0"; RECOVERED_AWS_REGION="$REGION_0"; RECOVERED_CLUSTER="$CLUSTER_0"
  SURVIVING_AWS_REGION="$REGION_1"; SURVIVING_CLUSTER="$CLUSTER_1"; SURVIVING_ALB="$ALB_ENDPOINT_1"
  : "${ZONE_PRIORITY:=1000}"
else
  RECOVERED_ZONE="$REGION_1"; RECOVERED_AWS_REGION="$REGION_1"; RECOVERED_CLUSTER="$CLUSTER_1"
  SURVIVING_AWS_REGION="$REGION_0"; SURVIVING_CLUSTER="$CLUSTER_0"; SURVIVING_ALB="$ALB_ENDPOINT_0"
  : "${ZONE_PRIORITY:=500}"
fi

SURVIVING_PREFIX="${SURVIVING_CLUSTER%-cluster}-oc"

log() { mgmt_log "$@"; }
err() { mgmt_err "$@"; }

wait_aurora_available() {
    local cluster_id=$1 region=$2 max_wait=${3:-600} elapsed=0 status
    log "Waiting for Aurora cluster ${cluster_id} in ${region} (timeout ${max_wait}s)..."
    while [ "${elapsed}" -lt "${max_wait}" ]; do
        status=$(aws rds describe-db-clusters --region "${region}" \
            --db-cluster-identifier "${cluster_id}" \
            --query 'DBClusters[0].Status' --output text 2>/dev/null || echo "unknown")
        [ "${status}" = "available" ] && { log "Aurora cluster ${cluster_id} is available."; return 0; }
        log "  Status: ${status} (${elapsed}s elapsed)"
        sleep 15; elapsed=$((elapsed + 15))
    done
    err "Timed out waiting for Aurora cluster ${cluster_id}."
    return 1
}

get_global_cluster_members() {
    aws rds describe-global-clusters \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --query 'GlobalClusters[0].GlobalClusterMembers' \
        --output json 2>/dev/null || echo "[]"
}

###############################################################################
# Step 0: Pre-flight                                                          #
###############################################################################

log "=== Step 0: Pre-flight ==="
log "Recovering zone:  ${RECOVERED_ZONE} (region ${FAILED_REGION})"
log "Surviving zone:   ${SURVIVING_AWS_REGION}"
log "Zone config:      numberOfReplicas=${ZONE_REPLICAS} priority=${ZONE_PRIORITY} numberOfBrokers=${ZONE_BROKERS}"
log ""

mgmt_topology_summary "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
  "BEFORE failback — ${RECOVERED_ZONE} absent"

###############################################################################
# Step 1: Aurora Global DB membership                                         #
###############################################################################

log ""
log "=== Step 1: Ensure ${RECOVERED_AWS_REGION} is an Aurora Global DB member ==="

MEMBERS=$(get_global_cluster_members)
MEMBER_COUNT=$(echo "${MEMBERS}" | jq 'length')

if [ "${MEMBER_COUNT}" = "0" ]; then
    err "Aurora Global Cluster ${AURORA_GLOBAL_CLUSTER_ID} not found or has no members."
    exit 1
fi

WRITER_ARN=$(echo "${MEMBERS}" | jq -r '.[] | select(.IsWriter == true) | .DBClusterArn')
log "Aurora writer is in: $(echo "${WRITER_ARN}" | awk -F':' '{print $4}')"

if [ "${MEMBER_COUNT}" = "1" ]; then
    log "Global DB has one member — the recovered region's cluster must be re-attached."
    err "This needs the regional cluster to exist first. If it was destroyed, run:"
    err "  terraform -chdir=${SCRIPT_DIR}/../terraform/infra apply"
    err "then re-run this script."
    exit 1
else
    log "Global DB has ${MEMBER_COUNT} members — nothing to re-attach."
fi

###############################################################################
# Step 2: Scale the recovered region back up                                  #
###############################################################################

log ""
log "=== Step 2: Scale up ECS services in ${RECOVERED_AWS_REGION} ==="

SERVICES=$(aws ecs list-services \
    --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
    --query 'serviceArns[]' --output text 2>/dev/null || echo "")

if [ -z "${SERVICES}" ]; then
    err "No ECS services found in ${RECOVERED_CLUSTER}."
    exit 1
fi

for service_arn in ${SERVICES}; do
    service_name="${service_arn##*/}"
    # modules/ecs/fargate/orchestration-cluster names its service
    # "<prefix>-orchestration-cluster"; connectors is "<prefix>-connectors".
    if [[ "${service_name}" == *-orchestration-cluster ]]; then
        desired="${ZONE_BROKERS}"
    else
        desired=1
    fi
    log "  Scaling ${service_name} -> ${desired} tasks..."
    aws ecs update-service \
        --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --service "${service_arn}" --desired-count "${desired}" \
        --no-cli-pager > /dev/null
done

###############################################################################
# Step 3: Wait for the brokers to rejoin membership                           #
###############################################################################

log ""
log "=== Step 3: Wait for ${RECOVERED_ZONE} brokers to rejoin membership ==="
log "  (they join as members but host no partitions until the zone is re-added)"

TARGET_BROKERS=$(( ZONE_BROKERS * 2 ))
ELAPSED=0
MAX_WAIT=900
while [ "${ELAPSED}" -lt "${MAX_WAIT}" ]; do
    TOPOLOGY=$(curl -sf --max-time 15 -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "http://${SURVIVING_ALB}/v2/topology" 2>/dev/null || echo "")
    if [ -n "${TOPOLOGY}" ]; then
        JOINED=$(echo "${TOPOLOGY}" | jq --arg z "${RECOVERED_ZONE}" \
            '[.brokers[] | select(.brokerId | startswith($z + "_"))] | length' 2>/dev/null || echo 0)
        if [ "${JOINED}" -ge "${ZONE_BROKERS}" ]; then
            log "  All ${JOINED} ${RECOVERED_ZONE} brokers are back in membership."
            break
        fi
        log "  [${ELAPSED}s] ${JOINED}/${ZONE_BROKERS} ${RECOVERED_ZONE} brokers joined..."
    else
        log "  [${ELAPSED}s] Gateway not reachable yet..."
    fi
    sleep 30; ELAPSED=$((ELAPSED + 30))
done

if [ "${ELAPSED}" -ge "${MAX_WAIT}" ]; then
    err "Timed out waiting for ${RECOVERED_ZONE} brokers to rejoin."
    exit 1
fi

###############################################################################
# Step 4: Re-add the zone                                                     #
###############################################################################

log ""
log "=== Step 4: Re-add zone ${RECOVERED_ZONE} ==="

if ! mgmt_tunnel_open "${SURVIVING_AWS_REGION}" "${SURVIVING_CLUSTER}" \
                      "${SURVIVING_PREFIX}" "${AWS_PROFILE:-}"; then
    err "Could not open a tunnel to the management API; the zone cannot be re-added."
    exit 1
fi

if mgmt_get /actuator/cluster | jq -e --arg z "${RECOVERED_ZONE}" \
     '[.partitioning.zones[]?.name] | index($z)' > /dev/null 2>&1; then
    log "  Zone ${RECOVERED_ZONE} is already in the partition distribution — skipping."
else
    QUERY=""
    [[ "$DRY_RUN" == "true" ]] && QUERY="?dryRun=true"

    # numberOfBrokers derives IDs <zone>_0 .. <zone>_<n-1>, which is exactly how
    # the brokers of a zone-aware cluster name themselves.
    PAYLOAD=$(jq -nc \
        --argjson replicas "${ZONE_REPLICAS}" \
        --argjson priority "${ZONE_PRIORITY}" \
        --argjson brokers  "${ZONE_BROKERS}" \
        '{numberOfReplicas: $replicas, priority: $priority, numberOfBrokers: $brokers}')

    log "  POST /actuator/cluster/zones/${RECOVERED_ZONE}${QUERY}"
    log "       ${PAYLOAD}"
    BODY=$(mgmt_request POST "/actuator/cluster/zones/${RECOVERED_ZONE}${QUERY}" "${PAYLOAD}")

    HTTP_CODE="$(mgmt_last_code)"
    if [[ ! "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
        err "Zone re-add rejected (HTTP ${HTTP_CODE}):"
        echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
        exit 1
    fi
    log "  Accepted (HTTP ${HTTP_CODE})."

    if [[ "$DRY_RUN" == "true" ]]; then
        log ""
        log "Dry run only — nothing was changed. Planned operations:"
        echo "${BODY}" | jq -r '
          "  changeId:   \(.changeId)",
          "  operations: \(.plannedChanges | length)",
          ([.plannedChanges[].operation] | group_by(.)
            | map("    \(length)x \(.[0])") | .[])
        ' 2>/dev/null || echo "${BODY}"
        exit 0
    fi

    CHANGE_ID=$(echo "${BODY}" | jq -r '.changeId // .pendingChange.id // .lastChange.id // empty' 2>/dev/null)
    if [[ -z "${CHANGE_ID}" ]]; then
        err "No changeId in the response; cannot poll the change."
        echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
        exit 1
    fi

    log ""
    log "=== Step 5: Wait for partition redistribution ==="
    log "  changeId=${CHANGE_ID}"
    if ! mgmt_wait_change "${CHANGE_ID}" 1800; then
        err "Zone re-add did not complete. Inspect: GET /actuator/cluster/changes/${CHANGE_ID}"
        exit 1
    fi
fi

mgmt_tunnel_close

###############################################################################
# Step 6: Verify                                                              #
###############################################################################

log ""
log "=== Step 6: Verify ==="

mgmt_topology_summary "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
  "AFTER failback — ${RECOVERED_ZONE} restored"

TOPOLOGY=$(curl -sf --max-time 20 -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "http://${SURVIVING_ALB}/v2/topology" 2>/dev/null || echo "")
BROKERS=$(echo "${TOPOLOGY}" | jq '.brokers | length' 2>/dev/null || echo 0)
PARTITIONS=$(echo "${TOPOLOGY}" | jq '[.brokers[].partitions[].partitionId] | unique | length' 2>/dev/null || echo 0)
LEADERS=$(echo "${TOPOLOGY}" | jq '[.brokers[].partitions[] | select(.role == "leader")] | length' 2>/dev/null || echo 0)
IDLE=$(echo "${TOPOLOGY}" | jq --arg z "${RECOVERED_ZONE}" \
  '[.brokers[] | select(.brokerId | startswith($z + "_")) | select((.partitions | length) == 0)] | length' 2>/dev/null || echo 0)

if [ "${BROKERS}" -ne "${TARGET_BROKERS}" ]; then
    err "Expected ${TARGET_BROKERS} brokers, found ${BROKERS}."
    exit 1
fi
if [ "${IDLE}" -ne 0 ]; then
    err "${IDLE} ${RECOVERED_ZONE} broker(s) host no partitions — the zone re-add did not take effect."
    exit 1
fi
if [ "${LEADERS}" -ne "${PARTITIONS}" ]; then
    err "Only ${LEADERS} of ${PARTITIONS} partitions have a leader — not settled yet."
    exit 1
fi
log "✓ ${BROKERS} brokers, ${PARTITIONS} partitions, ${LEADERS} leaders, no idle brokers."

###############################################################################
# Step 7: Optionally switch the Aurora writer back                            #
###############################################################################

if [ "${SWITCH_WRITER}" = "true" ]; then
    log ""
    log "=== Step 7: Switch the Aurora writer to ${RECOVERED_AWS_REGION} ==="

    MEMBER_ARN=$(get_global_cluster_members | \
        jq -r --arg r "${RECOVERED_AWS_REGION}" '.[] | select(.DBClusterArn | contains($r)) | .DBClusterArn')

    if [ -z "${MEMBER_ARN}" ]; then
        err "Cannot find the ${RECOVERED_AWS_REGION} member in the Global DB."
        exit 1
    fi

    aws rds failover-global-cluster \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --target-db-cluster-identifier "${MEMBER_ARN}" \
        --no-cli-pager
    sleep 15
    wait_aurora_available "$(echo "${MEMBER_ARN}" | awk -F':' '{print $7}')" "${RECOVERED_AWS_REGION}"
    log "Aurora writer moved to ${RECOVERED_AWS_REGION}."
else
    log ""
    log "Skipping the writer switch (pass --switch-writer to move it back)."
fi

###############################################################################
# Summary                                                                     #
###############################################################################

# shellcheck disable=SC2016  # JMESPath uses literal backticks
FINAL_WRITER=$(aws rds describe-global-clusters \
    --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
    --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn' \
    --output text 2>/dev/null | awk -F':' '{print $4}')

log ""
log "════════════════════════════════════════════════════════════════"
log "Failback complete — zone ${RECOVERED_ZONE} re-added."
log ""
log "Aurora writer:  ${FINAL_WRITER}"
log "Brokers:        ${BROKERS} across both zones"
log "Partitions:     ${PARTITIONS}, all led"
log ""
log "Next step: ./verify_dual_region.sh"
log "════════════════════════════════════════════════════════════════"

#!/usr/bin/env bash

###############################################################################
# Failover: ECS Dual-Region Fargate                                           #
#                                                                             #
# Performs a controlled failover from one region to the other:                #
#   1. Scales down ECS services in the failed region (prevents split-brain)   #
#   2. Waits for Zeebe to auto-reconfigure around the missing brokers         #
#   3. If Zeebe does not self-heal within the timeout, force-reconfigures     #
#   4. Verifies the surviving region has quorum                               #
#                                                                             #
# Aurora Global Database is NOT touched — the JDBC failover plugin and AWS   #
# handle writer promotion automatically via the global cluster endpoint.      #
#                                                                             #
# Usage:                                                                      #
#   ./failover.sh [--failed-region 0|1] [--force-timeout <seconds>]          #
#                                                                             #
# Defaults:                                                                   #
#   --failed-region  0   (region 0 is the one being failed away from)        #
#   --force-timeout  120 (seconds to wait for auto-reconfigure before force) #
#                                                                             #
# Prerequisites:                                                              #
#   . ./export_environment_prerequisites.sh                                   #
###############################################################################

set -euo pipefail

: "${REGION_0:?REGION_0 must be set — source export_environment_prerequisites.sh first}"
: "${REGION_1:?REGION_1 must be set}"
: "${CLUSTER_0:?CLUSTER_0 must be set}"
: "${CLUSTER_1:?CLUSTER_1 must be set}"
: "${ALB_ENDPOINT_0:?ALB_ENDPOINT_0 must be set}"
: "${ALB_ENDPOINT_1:?ALB_ENDPOINT_1 must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set (default: admin)}"
: "${ADMIN_PASS:?ADMIN_PASS must be set}"

###############################################################################
# Argument parsing                                                            #
###############################################################################

FAILED_REGION="0"
FORCE_TIMEOUT=120

while [[ $# -gt 0 ]]; do
  case "$1" in
    --failed-region) FAILED_REGION="$2"; shift 2 ;;
    --force-timeout) FORCE_TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ "$FAILED_REGION" != "0" && "$FAILED_REGION" != "1" ]]; then
  echo "ERROR: --failed-region must be 0 or 1"
  exit 1
fi

# Derive surviving region and endpoints
if [[ "$FAILED_REGION" == "0" ]]; then
  FAILED_CLUSTER="$CLUSTER_0"
  FAILED_AWS_REGION="$REGION_0"
  SURVIVING_ALB="$ALB_ENDPOINT_1"
  # Region 0 = even broker IDs, Region 1 = odd
  BROKERS_TO_REMOVE="0,2,4,6"
else
  FAILED_CLUSTER="$CLUSTER_1"
  FAILED_AWS_REGION="$REGION_1"
  SURVIVING_ALB="$ALB_ENDPOINT_0"
  BROKERS_TO_REMOVE="1,3,5,7"
fi

MGMT_URL="http://${SURVIVING_ALB}"
RETRY_INTERVAL=15

###############################################################################
# Helpers                                                                     #
###############################################################################

log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

zeebe_topology() {
  curl -sf --max-time 15 \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${MGMT_URL}/v2/topology" 2>/dev/null || echo ""
}

zeebe_cluster_state() {
  curl -sf --max-time 15 \
    "${MGMT_URL}/actuator/cluster" 2>/dev/null || echo ""
}

# Returns 0 if Zeebe has no pending change and all partitions have a leader
zeebe_is_stable() {
  local state
  state=$(zeebe_cluster_state)
  [[ -z "$state" ]] && return 1
  # If pendingChange key is present, redistribution is still in progress
  if echo "$state" | jq -e '.pendingChange' > /dev/null 2>&1; then
    return 1
  fi
  # All partition replicas should have a LEADER role
  local leaderless
  leaderless=$(echo "$state" | jq '[
    .brokers[].partitions[] | select(.role == "leader")
  ] | length')
  [[ "$leaderless" -gt 0 ]] && return 0 || return 1
}

###############################################################################
# Pre-flight check                                                             #
###############################################################################

log "=== Pre-flight: verify surviving region is reachable ==="

if ! zeebe_topology > /dev/null; then
  err "Cannot reach Zeebe topology at ${MGMT_URL}"
  err "Is the surviving region (failed-region=${FAILED_REGION}) endpoint correct?"
  exit 1
fi

log "Surviving region is reachable."
log ""
log "Failing over region:  ${FAILED_REGION} (${FAILED_AWS_REGION})"
log "Surviving endpoint:   ${MGMT_URL}"
log "Brokers to remove:    [${BROKERS_TO_REMOVE}]"
log "Force timeout:        ${FORCE_TIMEOUT}s"
log ""

###############################################################################
# Step 1: Scale down ECS services in the failed region                        #
###############################################################################

log "=== Step 1: Scale down ECS services in region ${FAILED_REGION} (${FAILED_AWS_REGION}) ==="

SERVICES=$(aws ecs list-services \
  --region "${FAILED_AWS_REGION}" \
  --cluster "${FAILED_CLUSTER}" \
  --query 'serviceArns[]' \
  --output text 2>/dev/null || echo "")

if [[ -z "$SERVICES" ]]; then
  log "No services found in cluster ${FAILED_CLUSTER} — region may already be down."
else
  for service_arn in $SERVICES; do
    service_name=$(echo "${service_arn}" | awk -F'/' '{print $NF}')
    log "  Scaling down ${service_name} → 0 tasks..."
    aws ecs update-service \
      --region "${FAILED_AWS_REGION}" \
      --cluster "${FAILED_CLUSTER}" \
      --service "${service_arn}" \
      --desired-count 0 \
      --no-cli-pager > /dev/null
  done
  log "  Scaled down. Allowing 30s for connections to drain..."
  sleep 30
fi

###############################################################################
# Step 2: Wait for Zeebe to auto-reconfigure                                  #
###############################################################################

log ""
log "=== Step 2: Waiting up to ${FORCE_TIMEOUT}s for Zeebe to self-heal ==="

ELAPSED=0
AUTO_HEALED=false

while [[ "$ELAPSED" -lt "$FORCE_TIMEOUT" ]]; do
  if zeebe_is_stable; then
    BROKER_COUNT=$(zeebe_topology | jq '.brokers | length' 2>/dev/null || echo "0")
    log "  Zeebe cluster is stable with ${BROKER_COUNT} brokers after ${ELAPSED}s."
    AUTO_HEALED=true
    break
  fi

  STATE=$(zeebe_cluster_state)
  if [[ -n "$STATE" ]] && echo "$STATE" | jq -e '.pendingChange' > /dev/null 2>&1; then
    COMPLETED=$(echo "$STATE" | jq -r '.pendingChange.completedOperations // 0')
    TOTAL=$(echo "$STATE" | jq -r '.pendingChange.totalOperations // 0')
    log "  [${ELAPSED}s] Auto-reconfiguration in progress (${COMPLETED}/${TOTAL} operations)..."
  else
    log "  [${ELAPSED}s] Waiting for Zeebe to detect broker loss..."
  fi

  sleep "$RETRY_INTERVAL"
  ELAPSED=$((ELAPSED + RETRY_INTERVAL))
done

###############################################################################
# Step 3: Force-reconfigure if Zeebe did not self-heal                        #
###############################################################################

if [[ "$AUTO_HEALED" == "false" ]]; then
  log ""
  log "=== Step 3: Zeebe did not self-heal — forcing reconfiguration ==="
  log "  Removing brokers [${BROKERS_TO_REMOVE}] via PATCH /actuator/cluster?force=true..."

  RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH \
    "${MGMT_URL}/actuator/cluster?force=true" \
    -H "Content-Type: application/json" \
    -d "{\"brokers\":{\"remove\":[${BROKERS_TO_REMOVE}]}}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [[ "$HTTP_CODE" != "202" ]]; then
    err "Force reconfiguration failed (HTTP ${HTTP_CODE}):"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  PLANNED=$(echo "$BODY" | jq -r '.plannedChanges | length' 2>/dev/null || echo "unknown")
  log "  Accepted (HTTP 202), ${PLANNED} planned changes."
  log ""
  log "  Waiting for forced redistribution to complete..."

  ELAPSED=0
  MAX_WAIT=300
  while [[ "$ELAPSED" -lt "$MAX_WAIT" ]]; do
    sleep "$RETRY_INTERVAL"
    ELAPSED=$((ELAPSED + RETRY_INTERVAL))

    STATE=$(zeebe_cluster_state)
    if [[ -z "$STATE" ]]; then
      log "  [${ELAPSED}s] Cluster API not yet available (coordinator relocating)..."
      continue
    fi

    if echo "$STATE" | jq -e '.pendingChange' > /dev/null 2>&1; then
      COMPLETED=$(echo "$STATE" | jq -r '.pendingChange.completedOperations // 0')
      TOTAL=$(echo "$STATE" | jq -r '.pendingChange.totalOperations // 0')
      log "  [${ELAPSED}s] Redistribution in progress (${COMPLETED}/${TOTAL})..."
    else
      log "  Redistribution complete."
      break
    fi

    if [[ "$ELAPSED" -ge "$MAX_WAIT" ]]; then
      err "Timed out waiting for redistribution. Check CloudWatch logs."
      exit 1
    fi
  done
else
  log ""
  log "=== Step 3: Skipped — Zeebe self-healed, no force needed ==="
fi

###############################################################################
# Step 4: Verify surviving region                                             #
###############################################################################

log ""
log "=== Step 4: Verify cluster health ==="

TOPOLOGY=$(zeebe_topology)
if [[ -z "$TOPOLOGY" ]]; then
  err "Cannot reach topology endpoint at ${MGMT_URL}"
  err "Run verify_dual_region.sh to check status once the cluster stabilises."
  exit 1
fi

BROKER_COUNT=$(echo "$TOPOLOGY" | jq '.brokers | length')
CLUSTER_SIZE=$(echo "$TOPOLOGY" | jq '.clusterSize')
REPLICATION_FACTOR=$(echo "$TOPOLOGY" | jq '.replicationFactor')

log "Broker count:      ${BROKER_COUNT}"
log "Cluster size:      ${CLUSTER_SIZE}"
log "Replication factor: ${REPLICATION_FACTOR}"

echo "$TOPOLOGY" | jq -r '
  .brokers[] |
  "  Broker \(.nodeId) — partitions: \([.partitions[] | "\(.partitionId)(\(.role))"] | join(", "))"
'

if [[ "$BROKER_COUNT" -ge 4 ]]; then
  log ""
  log "✓ Sufficient brokers for quorum (>= 4)."
else
  err "Only ${BROKER_COUNT} brokers visible — quorum may be lost. Check CloudWatch logs."
  exit 1
fi

###############################################################################
# Summary                                                                     #
###############################################################################

log ""
log "════════════════════════════════════════════════════════════════"
if [[ "$AUTO_HEALED" == "true" ]]; then
  log "Failover complete — Zeebe self-healed without force reconfiguration."
else
  log "Failover complete — Zeebe reconfigured via force (brokers [${BROKERS_TO_REMOVE}] removed)."
fi
log ""
log "Failed region ${FAILED_REGION}:  scaled down (0 ECS tasks)"
log "Surviving region:       ${BROKER_COUNT} brokers active"
log "Aurora:                 handled automatically by AWS / JDBC failover plugin"
log ""
log "Next steps:"
log "  1. Verify workflows:   curl -u ${ADMIN_USER}:<pass> ${MGMT_URL}/v2/topology"
log "  2. Full health check:  ./verify_dual_region.sh"
log "  3. To restore:         ./failback.sh --failed-region ${FAILED_REGION}"
log "════════════════════════════════════════════════════════════════"

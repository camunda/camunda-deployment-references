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
#   Environment variables are sourced automatically from                      #
#   export_environment_prerequisites.sh unless already set in the shell.      #
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Declare expected exports so shellcheck can track them across the source boundary.
# shellcheck disable=SC2034
REGION_0="${REGION_0:-}" REGION_1="${REGION_1:-}"
# shellcheck disable=SC2034
CLUSTER_0="${CLUSTER_0:-}" CLUSTER_1="${CLUSTER_1:-}"
# shellcheck disable=SC2034
ALB_ENDPOINT_0="${ALB_ENDPOINT_0:-}" ALB_ENDPOINT_1="${ALB_ENDPOINT_1:-}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-}"

# Auto-source prerequisites if the key variables are not already in the environment.
if [[ -z "${REGION_0}" || -z "${CLUSTER_0}" || -z "${ADMIN_PASS}" ]]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/export_environment_prerequisites.sh"
fi

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
  SURVIVING_CLUSTER="$CLUSTER_1"
  SURVIVING_AWS_REGION="$REGION_1"
  SURVIVING_ALB="$ALB_ENDPOINT_1"
else
  FAILED_CLUSTER="$CLUSTER_1"
  FAILED_AWS_REGION="$REGION_1"
  SURVIVING_CLUSTER="$CLUSTER_0"
  SURVIVING_AWS_REGION="$REGION_0"
  SURVIVING_ALB="$ALB_ENDPOINT_0"
fi

# This cluster uses CAMUNDA_CLUSTER_PARTITIONING_SCHEME=ZONE_AWARE with
# CAMUNDA_CLUSTER_ZONE set to the AWS region name. In zone-aware clusters the
# legacy integer nodeId is only unique *within* its zone — the S3 node-id
# leaser hands out 0..brokers_per_region-1 independently in each region, so
# both regions' brokers can carry the same nodeId. The globally-unique
# identifier is `brokerId`, formatted "<zone>_<nodeId>" (e.g. "us-east-1_0").
# See https://github.com/camunda/camunda/commit/3c93915b5783120ac811739574434f9852ee18b3
# and PATCH /actuator/cluster's BrokerId schema, which rejects bare integers
# on zone-aware clusters. BROKERS_TO_REMOVE is therefore computed from the
# live topology below, not hardcoded.
FAILED_ZONE="$FAILED_AWS_REGION"

# MGMT_URL only reaches the REST/webapp port (8080) via the public ALB, where
# /v2/topology lives. The management port (9600) — where /actuator/cluster
# lives — has no ALB route (enable_alb_http_management_listener_rule=false in
# camunda.tf) and is unauthenticated, so it's deliberately not exposed on the
# public internet. /actuator/cluster calls instead run inside a running
# broker task via `aws ecs execute-command` (see exec_broker below), reaching
# localhost:9600 from within the task's own network namespace.
MGMT_URL="http://${SURVIVING_ALB}"
RETRY_INTERVAL=15

###############################################################################
# Helpers                                                                     #
###############################################################################

log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

if ! command -v session-manager-plugin > /dev/null 2>&1; then
  err "session-manager-plugin not found."
  err "It's required by 'aws ecs execute-command', used to reach the management"
  err "port (9600) which is intentionally not exposed on the public ALB."
  err "Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
  exit 1
fi

zeebe_topology() {
  curl -sf --max-time 15 \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${MGMT_URL}/v2/topology" 2>/dev/null || echo ""
}

# Finds a running orchestration-cluster task in the surviving region.
# Never propagates failure — under `set -e`, a plain assignment like
# `x=$(surviving_broker_task)` would abort the whole script on a transient
# AWS API error, which we want treated as "not available yet" instead.
surviving_broker_task() {
  local service_arn
  service_arn=$(aws ecs list-services \
    --region "${SURVIVING_AWS_REGION}" \
    --cluster "${SURVIVING_CLUSTER}" \
    --query "serviceArns[?contains(@, 'orchestration')] | [0]" \
    --output text 2>/dev/null) || true
  [[ -z "$service_arn" || "$service_arn" == "None" ]] && { echo ""; return; }

  aws ecs list-tasks \
    --region "${SURVIVING_AWS_REGION}" \
    --cluster "${SURVIVING_CLUSTER}" \
    --service-name "${service_arn##*/}" \
    --desired-status RUNNING \
    --query 'taskArns[0]' \
    --output text 2>/dev/null || true
}

# Runs a shell script inside a broker task via ECS Exec (SSM) and returns its
# stdout, stripped of the SSM session banner via a random marker. Always
# exits 0 (see surviving_broker_task comment above for why).
exec_broker() {
  local script="$1"
  local task_arn
  task_arn=$(surviving_broker_task)
  [[ -z "$task_arn" || "$task_arn" == "None" ]] && { echo ""; return; }

  local marker="___FAILOVER_${RANDOM}${RANDOM}___"
  local encoded
  encoded=$(printf '%s' "$script" | base64 | tr -d '\n')

  aws ecs execute-command \
    --region "${SURVIVING_AWS_REGION}" \
    --cluster "${SURVIVING_CLUSTER}" \
    --task "${task_arn}" \
    --container orchestration-cluster \
    --interactive \
    --command "/bin/sh -c 'echo ${marker}; echo ${encoded} | base64 -d | /bin/sh; echo ${marker}'" \
    2>/dev/null | tr -d '\r' | awk -v marker="${marker}" '
      $0 == marker { count++; next }
      count == 1 { print }
    ' || true
}

# The orchestration-cluster image (Minimus "MinimOS" base) has no curl —
# only wget (GNU Wget, supports --method) and nc are available inside it.
zeebe_cluster_state() {
  exec_broker 'wget -q -O - --timeout=15 http://localhost:9600/actuator/cluster 2>/dev/null' || echo ""
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

PREFLIGHT_TOPOLOGY=$(zeebe_topology)
if [[ -z "$PREFLIGHT_TOPOLOGY" ]]; then
  err "Cannot reach Zeebe topology at ${MGMT_URL}"
  err "Is the surviving region (failed-region=${FAILED_REGION}) endpoint correct?"
  exit 1
fi

log "Surviving region is reachable."

# Identify brokers belonging to the failed zone via the globally-unique
# brokerId ("<zone>_<nodeId>") rather than the zone-local nodeId.
BROKERS_TO_REMOVE_JSON=$(echo "$PREFLIGHT_TOPOLOGY" | jq -c \
  --arg prefix "${FAILED_ZONE}_" \
  '[.brokers[].brokerId | select(startswith($prefix))]')
BROKERS_TO_REMOVE_COUNT=$(echo "$BROKERS_TO_REMOVE_JSON" | jq 'length')

if [[ "$BROKERS_TO_REMOVE_COUNT" -eq 0 ]]; then
  err "No brokers found with zone prefix '${FAILED_ZONE}_' in the topology."
  err "Check that CAMUNDA_CLUSTER_ZONE for region ${FAILED_REGION} is indeed '${FAILED_ZONE}'."
  exit 1
fi

BROKERS_TO_REMOVE_DISPLAY=$(echo "$BROKERS_TO_REMOVE_JSON" | jq -r 'join(", ")')

log ""
log "Failing over region:  ${FAILED_REGION} (${FAILED_AWS_REGION})"
log "Surviving endpoint:   ${MGMT_URL}"
log "Brokers to remove:    [${BROKERS_TO_REMOVE_DISPLAY}]"
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
  log "  Removing brokers [${BROKERS_TO_REMOVE_DISPLAY}] via PATCH /actuator/cluster?force=true..."

  # No curl in the image — use wget --method=PATCH, capturing the status line
  # via -S (server-response) since wget doesn't expose it on stdout directly.
  # --content-on-error keeps the JSON error body on 4xx/5xx (wget drops it by
  # default). printf/$(...) guarantees exactly one trailing newline after the
  # body so the appended status code lands on its own line for `tail -1`.
  PATCH_SCRIPT=$(cat <<'EOF'
wget -q -S --content-on-error --method=PATCH --header='Content-Type: application/json' --body-data='{"brokers":{"remove":__BROKERS_JSON__}}' -O /tmp/.failover_body "http://localhost:9600/actuator/cluster?force=true" 2>/tmp/.failover_hdr
CODE=$(grep -oE 'HTTP/[0-9.]+ [0-9]+' /tmp/.failover_hdr | tail -1 | awk '{print $2}')
printf '%s\n' "$(cat /tmp/.failover_body)"
echo "$CODE"
rm -f /tmp/.failover_body /tmp/.failover_hdr
EOF
)
  PATCH_SCRIPT="${PATCH_SCRIPT//__BROKERS_JSON__/$BROKERS_TO_REMOVE_JSON}"
  RESPONSE=$(exec_broker "$PATCH_SCRIPT")

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
  "  Broker \(.brokerId) — partitions: \([.partitions[] | "\(.partitionId)(\(.role))"] | join(", "))"
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
  log "Failover complete — Zeebe reconfigured via force (brokers [${BROKERS_TO_REMOVE_DISPLAY}] removed)."
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

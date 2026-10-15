#!/usr/bin/env bash

###############################################################################
# Failover: ECS Dual-Region Fargate                                           #
#                                                                             #
# Removes a whole zone from the zone-aware cluster after that region is lost:  #
#   1. Prints the topology before the change                                  #
#   2. Scales the failed region's ECS services to zero                        #
#   3. Force-removes the zone via DELETE /actuator/cluster/zones/{zoneId}     #
#   4. Polls the change to COMPLETED                                          #
#   5. Moves the Aurora writer out of the failed region                        #
#   6. Prints the topology after, and checks every partition has a leader     #
#                                                                             #
# Why a zone, not a broker list                                               #
#   This reference runs a zone-aware cluster (CAMUNDA_CLUSTER_PARTITIONING_    #
#   SCHEME=ZONE_AWARE) whose zone names are the AWS region names and whose    #
#   broker IDs are "<zone>_<n>", e.g. eu-central-1_0. The Zones API removes    #
#   the zone and its brokers from the persisted partition distribution in one  #
#   atomic change, so there is no per-broker ID list to keep in sync.          #
#                                                                             #
# Why force=true                                                              #
#   The API now defaults to force=false, which gracefully drains the zone's    #
#   partitions and therefore needs its brokers still running. Failover is the  #
#   opposite situation: the region is gone. force=true evicts the unreachable  #
#   brokers instead of waiting for them.                                      #
#                                                                             #
#   With replicationFactor 4 across 2 zones, each partition keeps 2 replicas   #
#   per zone. Losing a zone leaves 2 of 4 — not a majority — so the affected   #
#   partitions have no quorum until the zone is removed. Removing it is what   #
#   restores availability; there is nothing to wait for first.                 #
#                                                                             #
# Aurora Global Database does not move its writer on its own. When the writer  #
# is in the failed region, Step 5 runs a planned switchover to the surviving   #
# region and waits until the global cluster reports it finished. The JDBC      #
# failover plugin then follows the new writer.                                 #
#                                                                             #
# Usage:                                                                      #
#   ./failover.sh [--failed-region 0|1] [--dry-run] [--keep-tasks]            #
#                 [--keep-writer]                                             #
#                                                                             #
# Defaults:                                                                   #
#   --failed-region  0    (region 0 is the one being failed away from)        #
#   --dry-run        off  (adds dryRun=true; validates without changing)      #
#   --keep-tasks     off  (skip the ECS scale-down; use when already down)    #
#   --keep-writer    off  (skip the Aurora switchover; use when the failed    #
#                          region's Aurora is down too, then follow the AWS   #
#                          unplanned recovery procedure)                      #
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
: "${ALB_ENDPOINT_0:?ALB_ENDPOINT_0 must be set}"
: "${ALB_ENDPOINT_1:?ALB_ENDPOINT_1 must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set (default: admin)}"
: "${ADMIN_PASS:?ADMIN_PASS must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=SCRIPTDIR/zeebe_management_api.sh
. "${SCRIPT_DIR}/zeebe_management_api.sh"
# shellcheck source=SCRIPTDIR/aurora.sh
. "${SCRIPT_DIR}/aurora.sh"

###############################################################################
# Argument parsing                                                            #
###############################################################################

FAILED_REGION="0"
DRY_RUN=false
KEEP_TASKS=false
KEEP_WRITER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --failed-region) FAILED_REGION="$2"; shift 2 ;;
    --dry-run)       DRY_RUN=true; shift ;;
    --keep-tasks)    KEEP_TASKS=true; shift ;;
    --keep-writer)   KEEP_WRITER=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ "$FAILED_REGION" != "0" && "$FAILED_REGION" != "1" ]]; then
  echo "ERROR: --failed-region must be 0 or 1"
  exit 1
fi

# The zone name is the AWS region name: terraform/app/locals.tf sets
# CAMUNDA_CLUSTER_PARTITIONING_ZONEAWARE_ZONES_{0,1}_NAME to region_{0,1}.
if [[ "$FAILED_REGION" == "0" ]]; then
  FAILED_ZONE="$REGION_0";   FAILED_AWS_REGION="$REGION_0";   FAILED_CLUSTER="$CLUSTER_0"
  SURVIVING_AWS_REGION="$REGION_1"; SURVIVING_CLUSTER="$CLUSTER_1"; SURVIVING_ALB="$ALB_ENDPOINT_1"
else
  FAILED_ZONE="$REGION_1";   FAILED_AWS_REGION="$REGION_1";   FAILED_CLUSTER="$CLUSTER_1"
  SURVIVING_AWS_REGION="$REGION_0"; SURVIVING_CLUSTER="$CLUSTER_0"; SURVIVING_ALB="$ALB_ENDPOINT_0"
fi

# "<cluster_name>-rN-cluster" -> "<cluster_name>-rN-oc", the module prefix.
SURVIVING_PREFIX="${SURVIVING_CLUSTER%-cluster}-oc"

log() { mgmt_log "$@"; }
err() { mgmt_err "$@"; }

# Sets WRITER_ARN and TARGET_ARN (the member in the surviving region), or exits.
aurora_read_members() {
  local global members
  # A rerun can find the previous run's switchover still going: decide from
  # the settled membership, never start a second switchover.
  if ! global=$(aurora_settled_global "${SURVIVING_AWS_REGION}"); then
    err "Could not read a settled Aurora global cluster."
    exit 1
  fi
  members=$(echo "${global}" | jq '.GlobalClusterMembers')
  WRITER_ARN=$(echo "${members}" | jq -r '.[] | select(.IsWriter == true) | .DBClusterArn')
  if [[ -z "${WRITER_ARN}" ]]; then
    err "No Aurora writer ARN in the global cluster."
    exit 1
  fi
  TARGET_ARN=$(echo "${members}" | jq -r --arg r "${SURVIVING_AWS_REGION}" \
    '[.[] | select((.DBClusterArn | split(":")[3]) == $r)][0].DBClusterArn // empty')
  if [[ -z "${TARGET_ARN}" ]]; then
    err "No Aurora member in ${SURVIVING_AWS_REGION} to promote."
    exit 1
  fi
}

# Step 2 and 3: force-removes FAILED_ZONE and waits for the change, or prints
# the planned change on a dry run. A rerun finds the zone already gone and
# sends no second request.
remove_failed_zone() {
  local present=0 query="force=true" body change_id
  mgmt_zone_present "${FAILED_ZONE}" || present=$?
  case "${present}" in
    1) log "  Zone ${FAILED_ZONE} is already absent — skipping removal."
       return 0 ;;
    2) err "Could not read the partition distribution; zone removal cannot proceed."
       exit 1 ;;
  esac

  [[ "$DRY_RUN" == "true" ]] && query="${query}&dryRun=true"
  log "  DELETE /actuator/cluster/zones/${FAILED_ZONE}?${query}"
  if ! body=$(mgmt_request DELETE "/actuator/cluster/zones/${FAILED_ZONE}?${query}"); then
    err "Zone removal rejected; see the response above."
    exit 1
  fi
  log "  Accepted."

  if [[ "$DRY_RUN" == "true" ]]; then
    log ""
    log "Dry run only — nothing was changed. Planned operations:"
    echo "${body}" | jq -r '
      "  changeId:   \(.changeId)",
      "  operations: \(.plannedChanges | length)",
      ([.plannedChanges[].operation] | group_by(.)
        | map("    \(length)x \(.[0])") | .[])
    ' 2>/dev/null || echo "${body}"
    return 0
  fi

  log ""
  log "=== Step 3: Wait for the change to complete ==="
  change_id=$(echo "${body}" | jq -r '.changeId // .pendingChange.id // .lastChange.id // empty' 2>/dev/null)
  if [[ -z "${change_id}" ]]; then
    err "No changeId in the response; cannot poll the change deterministically."
    echo "${body}" | jq . 2>/dev/null || echo "${body}"
    exit 1
  fi
  log "  changeId=${change_id}"
  if ! mgmt_wait_change "${change_id}" 900; then
    err "Zone removal did not complete. Inspect: GET /actuator/cluster/changes/${change_id}"
    exit 1
  fi
}

# Step 5: moves the Aurora writer out of the failed region, or on a dry run
# says what it would do. Sets AURORA_SUMMARY for the final report.
move_aurora_writer() {
  if [[ -z "${AURORA_GLOBAL_CLUSTER_ID:-}" ]]; then
    log "  Aurora: AURORA_GLOBAL_CLUSTER_ID is not set, skipping."
    AURORA_SUMMARY="not managed (AURORA_GLOBAL_CLUSTER_ID unset)"
    return 0
  fi
  if [[ "$KEEP_WRITER" == "true" ]]; then
    log "  Aurora: --keep-writer given, leaving the writer where it is."
    log "  If it was in ${FAILED_AWS_REGION}, recover it with the Aurora Global Database"
    log "  unplanned recovery procedure; exporting waits until a writer is available."
    AURORA_SUMMARY="left in place (--keep-writer)"
    return 0
  fi

  aurora_read_members
  local writer_region
  writer_region=$(echo "${WRITER_ARN}" | cut -d: -f4)
  if [[ "${writer_region}" != "${FAILED_AWS_REGION}" ]]; then
    log "  Aurora: the writer is in ${writer_region}, not in the failed region."
    AURORA_SUMMARY="writer in ${writer_region}"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "  --dry-run: would promote ${TARGET_ARN}, doing nothing."
    return 0
  fi

  aurora_planned_switch "${WRITER_ARN}" "${TARGET_ARN}" || exit 1
  AURORA_SUMMARY="writer moved to ${SURVIVING_AWS_REGION}"
}

###############################################################################
# Step 0: Pre-flight                                                          #
###############################################################################

log "=== Step 0: Pre-flight ==="
log "Failing over zone:    ${FAILED_ZONE} (region ${FAILED_REGION})"
log "Surviving zone:       ${SURVIVING_AWS_REGION}"
log "Surviving ALB:        http://${SURVIVING_ALB}"
log "Mode:                 force=true$([ "$DRY_RUN" = true ] && echo ", dryRun=true")"
log ""

if ! curl -sf --max-time 15 -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "http://${SURVIVING_ALB}/v2/topology" > /dev/null 2>&1; then
  err "Cannot reach the surviving region's gateway at http://${SURVIVING_ALB}"
  exit 1
fi
log "Surviving region is reachable."

mgmt_topology_summary "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
  "BEFORE failover — both zones present"

###############################################################################
# Step 1: Scale down the failed region                                        #
###############################################################################

log ""
log "=== Step 1: Scale down ECS services in ${FAILED_AWS_REGION} ==="

if [[ "$DRY_RUN" == "true" ]]; then
  # A dry run must not take the region offline: the whole point is to validate
  # the request without changing anything.
  log "  --dry-run given, leaving ECS untouched."
elif [[ "$KEEP_TASKS" == "true" ]]; then
  log "  --keep-tasks given, leaving ECS untouched."
else
  SERVICES=$(aws ecs list-services \
    --region "${FAILED_AWS_REGION}" --cluster "${FAILED_CLUSTER}" \
    --query 'serviceArns[]' --output text 2>/dev/null || echo "")

  if [[ -z "$SERVICES" ]]; then
    log "  No services in ${FAILED_CLUSTER} — region already down."
  else
    for service_arn in ${SERVICES}; do
      service_name="${service_arn##*/}"
      log "  Scaling ${service_name} -> 0 tasks..."
      aws ecs update-service \
        --region "${FAILED_AWS_REGION}" --cluster "${FAILED_CLUSTER}" \
        --service "${service_arn}" --desired-count 0 \
        --no-cli-pager > /dev/null
    done
    log "  Scaled down. Allowing 30s for the brokers to drop out of membership..."
    sleep 30
  fi
fi

###############################################################################
# Step 2: Force-remove the zone                                               #
###############################################################################

log ""
log "=== Step 2: Remove zone ${FAILED_ZONE} ==="

# The management API is on port 9600 and is not published through the ALB
# (terraform/infra/lb.tf gives that listener a fixed-response default), so
# reach it over the ECS Exec / Session Manager channel.
if ! mgmt_tunnel_open "${SURVIVING_AWS_REGION}" "${SURVIVING_CLUSTER}" \
                      "${SURVIVING_PREFIX}" "${AWS_PROFILE:-}"; then
  err "Could not open a tunnel to the management API."
  err "Without it the zone cannot be removed. Fix the tunnel and re-run."
  exit 1
fi

remove_failed_zone

if [[ "$DRY_RUN" == "true" ]]; then
  move_aurora_writer
  exit 0
fi

###############################################################################
# Step 4: Verify                                                              #
###############################################################################

log ""
log "=== Step 4: Verify ==="

# `|| ZONE_STATE=$?` rather than a bare call: set -e would kill the script on a
# non-zero return before $? could be read, and here 1 ("zone absent") is the
# success path.
ZONE_STATE=0
mgmt_zone_present "${FAILED_ZONE}" || ZONE_STATE=$?
case "${ZONE_STATE}" in
  0) err "Zone ${FAILED_ZONE} is still in the partition distribution — removal incomplete."
     exit 1 ;;
  2) err "Could not read the partition distribution, so the removal cannot be confirmed."
     err "Check manually: GET /actuator/cluster"
     exit 1 ;;
  *) log "  Zone ${FAILED_ZONE} is gone from the partition distribution." ;;
esac

mgmt_tunnel_close

###############################################################################
# Step 5: Aurora writer                                                       #
###############################################################################

log ""
log "=== Step 5: Aurora writer ==="
move_aurora_writer

###############################################################################
# Step 6: Verify leaders                                                      #
###############################################################################

mgmt_topology_summary "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
  "AFTER failover — ${FAILED_ZONE} removed"

TOPOLOGY=$(curl -sf --max-time 20 -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "http://${SURVIVING_ALB}/v2/topology" 2>/dev/null || echo "")
LEADERS=$(echo "${TOPOLOGY}" | jq '[.brokers[].partitions[] | select(.role == "leader")] | length' 2>/dev/null || echo 0)
PARTITIONS=$(echo "${TOPOLOGY}" | jq '[.brokers[].partitions[].partitionId] | unique | length' 2>/dev/null || echo 0)

if [[ "${LEADERS}" -eq "${PARTITIONS}" ]] && [[ "${PARTITIONS}" -gt 0 ]]; then
  log "✓ Every partition has a leader (${LEADERS}/${PARTITIONS})."
else
  err "Only ${LEADERS} of ${PARTITIONS} partitions have a leader — cluster not yet settled."
  err "Re-check with: ./verify_dual_region.sh"
  exit 1
fi

log ""
log "════════════════════════════════════════════════════════════════"
log "Failover complete — zone ${FAILED_ZONE} force-removed."
log ""
log "Failed region ${FAILED_REGION}:  ECS scaled to 0, zone dropped from the distribution"
log "Surviving zone:         ${SURVIVING_AWS_REGION}, ${LEADERS}/${PARTITIONS} partitions led"
log "Aurora:                 ${AURORA_SUMMARY}"
log ""
log "Next steps:"
log "  1. Create work:  curl -u ${ADMIN_USER}:<pass> http://${SURVIVING_ALB}/v2/topology"
log "  2. Health check: ./verify_dual_region.sh"
log "  3. Restore:      ./failback.sh --failed-region ${FAILED_REGION}"
log "════════════════════════════════════════════════════════════════"

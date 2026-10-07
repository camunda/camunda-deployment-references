#!/usr/bin/env bash

###############################################################################
# Failover: ECS Dual-Region Fargate                                           #
#                                                                             #
# Removes a whole zone from the zone-aware cluster after that region is lost:  #
#   1. Prints the topology before the change                                  #
#   2. Scales the failed region's ECS services to zero                        #
#   3. Promotes the surviving Aurora member, if the writer was in the         #
#      failed region                                                          #
#   4. Force-removes the zone via DELETE /actuator/cluster/zones/{zoneId}     #
#   5. Polls the change to COMPLETED                                          #
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
# The database                                                                #
#   Aurora Global Database has a single writer region, so losing the          #
#   writer's region leaves the database read-only until a survivor is         #
#   promoted. AWS does not do that by itself, and the JDBC failover           #
#   plugin can only discover a writer that exists — so the runbook            #
#   promotes it, as aws/kubernetes/eks-multi-region-rdbms does.               #
#                                                                             #
#   A writer already outside the failed region needs nothing, so no           #
#   flag gates this: the global cluster's own state decides.                  #
#                                                                             #
# Usage:                                                                      #
#   ./failover.sh [--failed-region 0|1] [--dry-run] [--keep-tasks]            #
#                                                                             #
# Defaults:                                                                   #
#   --failed-region  0    (region 0 is the one being failed away from)        #
#   --dry-run        off  (adds dryRun=true; validates without changing)      #
#   --keep-tasks     off  (skip the ECS scale-down; use when already down)    #
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

###############################################################################
# Argument parsing                                                            #
###############################################################################

FAILED_REGION="0"
DRY_RUN=false
KEEP_TASKS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --failed-region) FAILED_REGION="$2"; shift 2 ;;
    --dry-run)       DRY_RUN=true; shift ;;
    --keep-tasks)    KEEP_TASKS=true; shift ;;
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
    log "  Scaled down."
  fi
fi

###############################################################################
# Step 2: Database writer                                                     #
###############################################################################

log ""
log "=== Step 2: Aurora Global writer ==="

# Guard clauses rather than nesting: two of the three exits only report, and
# the promotion is the single interesting path.
promote_aurora_writer() {
  if [[ -z "${AURORA_GLOBAL_CLUSTER_ID:-}" ]]; then
    log "  No Aurora Global cluster in this deployment — secondary storage is"
    log "  OpenSearch, or the database is bring-your-own. Nothing to promote."
    return 0
  fi

  local members writer_region target_arn target_region
  members=$(aws rds describe-global-clusters \
    --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
    --query 'GlobalClusters[0].GlobalClusterMembers' --output json)

  # One jq pass for both answers: it already splits the ARN, so there is no
  # need for a second `echo | cut` round trip.
  writer_region=$(echo "${members}" | jq -r \
    'first(.[] | select(.IsWriter == true) | .DBClusterArn | split(":")[3]) // empty')

  log "  Current writer region: ${writer_region:-unknown}"

  if [[ "${writer_region}" != "${FAILED_AWS_REGION}" ]]; then
    log "  The writer is not in the failed region — no database action required."
    return 0
  fi

  # A member that is neither the current writer nor in the failed region. With
  # two regions that is exactly the survivor; selecting it this way stays
  # correct if a third member is ever added.
  target_arn=$(echo "${members}" | jq -r --arg failed "${FAILED_AWS_REGION}" \
    'first(.[] | select(.IsWriter != true) | select((.DBClusterArn | split(":")[3]) != $failed) | .DBClusterArn) // empty')

  if [[ -z "${target_arn}" ]]; then
    err "No surviving Aurora member to promote — the database stays read-only."
    err "Check: aws rds describe-global-clusters --global-cluster-identifier ${AURORA_GLOBAL_CLUSTER_ID}"
    return 1
  fi

  target_region=$(echo "${target_arn}" | cut -d: -f4)

  if [[ "${DRY_RUN}" == true ]]; then
    log "  --dry-run: would promote ${target_arn} (${target_region}), doing nothing."
    return 0
  fi

  log "  Promoting ${target_arn} (${target_region})"
  # A switchover: it waits for the target to catch up, so there is no data
  # loss. It does need the failed region's cluster to still answer — a loss
  # where it does not needs the AWS detach-and-promote procedure, which is
  # lossy and one-way and therefore not automated in a reference runbook.
  aws rds failover-global-cluster \
    --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
    --target-db-cluster-identifier "${target_arn}" \
    --no-cli-pager >/dev/null

  # Poll for the writer actually having moved, not for the cluster reporting
  # `available`. The CLI's own db-cluster-available waiter watches the wrong
  # field (DBClusters[].Status) on a 30s/60-attempt schedule, so it rounds
  # every run up to a 30s multiple and can block for half an hour.
  local waited=0
  while [[ "${waited}" -lt "${WRITER_PROMOTION_TIMEOUT}" ]]; do
    if [[ "$(aurora_writer_region)" == "${target_region}" ]]; then
      log "  ✓ Writer is now in ${target_region} (after ${waited}s)."
      log "    The AWS Advanced JDBC Wrapper failover plugin discovers it from"
      log "    the global endpoint, so Camunda needs no restart; connections in"
      log "    flight during the promotion are retried by the driver."
      return 0
    fi
    sleep "${WRITER_POLL_INTERVAL}"
    waited=$((waited + WRITER_POLL_INTERVAL))
  done

  # Do not abort here: step 3 is what restores Zeebe quorum, and holding it
  # behind a slow database would extend the outage this script exists to end.
  # But do not call it a success either — record it, and exit non-zero at the
  # end, so automation and operators are not told failover completed while the
  # surviving region is still read-only.
  WRITER_PROMOTION_FAILED=true
  log "  ⚠ Writer has not shown as ${target_region} after ${WRITER_PROMOTION_TIMEOUT}s."
  log "    Continuing to the zone removal — the promotion may still be in flight."
  log "    Confirm with: ./verify_dual_region.sh before treating failover as done."
  return 0
}

# aurora_writer_region echoes the region of the current writer, or nothing.
aurora_writer_region() {
  # shellcheck disable=SC2016  # JMESPath uses literal backticks
  aws rds describe-global-clusters \
    --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
    --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn' \
    --output text 2>/dev/null | awk -F':' '{print $4}'
}

WRITER_PROMOTION_TIMEOUT=600
WRITER_POLL_INTERVAL=15
# Set when the promotion was issued but no writer appeared in time; the script
# finishes its Zeebe work and then exits non-zero.
WRITER_PROMOTION_FAILED=false

promote_aurora_writer

###############################################################################
# Step 3: Force-remove the zone                                               #
###############################################################################

log ""
log "=== Step 3: Remove zone ${FAILED_ZONE} ==="

# Give the scaled-down brokers a moment to leave membership. Belt and braces:
# the removal below passes force=true, which evicts unreachable brokers rather
# than waiting for them, and Step 2 has usually just spent longer than this.
if [[ "${KEEP_TASKS}" == false && "${DRY_RUN}" == false ]]; then
  sleep 15
fi

# The management API is on port 9600 and is not published through the ALB
# (terraform/infra/lb.tf gives that listener a fixed-response default), so
# reach it over the ECS Exec / Session Manager channel.
if ! mgmt_tunnel_open "${SURVIVING_AWS_REGION}" "${SURVIVING_CLUSTER}" \
                      "${SURVIVING_PREFIX}" "${AWS_PROFILE:-}"; then
  err "Could not open a tunnel to the management API."
  err "Without it the zone cannot be removed. Fix the tunnel and re-run."
  exit 1
fi

QUERY="force=true"
[[ "$DRY_RUN" == "true" ]] && QUERY="${QUERY}&dryRun=true"

log "  DELETE /actuator/cluster/zones/${FAILED_ZONE}?${QUERY}"
if ! BODY=$(mgmt_request DELETE "/actuator/cluster/zones/${FAILED_ZONE}?${QUERY}"); then
  err "Zone removal rejected; see the response above."
  exit 1
fi
log "  Accepted."

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

###############################################################################
# Step 4: Wait for the change to complete                                     #
###############################################################################

log ""
log "=== Step 4: Wait for the change to complete ==="

if [[ -z "${CHANGE_ID}" ]]; then
  err "No changeId in the response; cannot poll the change deterministically."
  echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
  exit 1
fi

log "  changeId=${CHANGE_ID}"
if ! mgmt_wait_change "${CHANGE_ID}" 900; then
  err "Zone removal did not complete. Inspect: GET /actuator/cluster/changes/${CHANGE_ID}"
  exit 1
fi

###############################################################################
# Step 5: Verify                                                              #
###############################################################################

log ""
log "=== Step 5: Verify ==="

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

mgmt_topology_summary "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
  "AFTER failover — ${FAILED_ZONE} removed"

# Re-election is not instantaneous, and it is not part of the cluster change:
# the change reaching COMPLETED means the zone has left the distribution, not
# that every partition has already chosen a new leader from the replicas that
# remain. Measured on a live stack, 5 of 8 partitions had a leader the moment
# the change completed and the rest followed within a minute, so a single-shot
# check here fails a failover that is in fact succeeding.
LEADER_TIMEOUT=300
LEADER_POLL_INTERVAL=10
waited=0
LEADERS=0
PARTITIONS=0

while :; do
  TOPOLOGY=$(curl -sf --max-time 20 -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "http://${SURVIVING_ALB}/v2/topology" 2>/dev/null || echo "")
  # Count partitions that have exactly one leader, not leader entries: two
  # leaders on one partition must not make up for none on another.
  LEADERS=$(echo "${TOPOLOGY}" | jq '
    [.brokers[].partitions[] | select(.role == "leader") | .partitionId]
    | group_by(.) | map(select(length == 1)) | length' 2>/dev/null || echo 0)
  PARTITIONS=$(echo "${TOPOLOGY}" | jq '[.brokers[].partitions[].partitionId] | unique | length' 2>/dev/null || echo 0)

  if [[ "${LEADERS}" -eq "${PARTITIONS}" ]] && [[ "${PARTITIONS}" -gt 0 ]]; then
    log "✓ Every partition has a leader (${LEADERS}/${PARTITIONS}) after ${waited}s."
    break
  fi

  if [[ "${waited}" -ge "${LEADER_TIMEOUT}" ]]; then
    err "Only ${LEADERS} of ${PARTITIONS} partitions have a leader after ${LEADER_TIMEOUT}s."
    err "The zone was removed, so this is re-election not finishing rather than"
    err "the removal failing. Re-check with: ./verify_dual_region.sh"
    exit 1
  fi

  log "  [${waited}s] ${LEADERS}/${PARTITIONS} partitions led, waiting for re-election..."
  sleep "${LEADER_POLL_INTERVAL}"
  waited=$((waited + LEADER_POLL_INTERVAL))
done

###############################################################################
# Summary                                                                     #
###############################################################################

log ""
log "════════════════════════════════════════════════════════════════"
log "Failover complete — zone ${FAILED_ZONE} force-removed."
log ""
log "Failed region ${FAILED_REGION}:  ECS scaled to 0, zone dropped from the distribution"
log "Surviving zone:         ${SURVIVING_AWS_REGION}, ${LEADERS}/${PARTITIONS} partitions led"
if [[ -n "${AURORA_GLOBAL_CLUSTER_ID:-}" ]]; then
  log "Aurora writer:          $(aurora_writer_region)"
fi
log ""
log "Next steps:"
log "  1. Create work:  curl -u ${ADMIN_USER}:<pass> http://${SURVIVING_ALB}/v2/topology"
log "  2. Health check: ./verify_dual_region.sh"
# --switch-writer, because step 2 moved the writer out of the failed region:
# failback without it restores the brokers and leaves the database where it is.
log "  3. Restore:      ./failback.sh --failed-region ${FAILED_REGION} --switch-writer"
log "════════════════════════════════════════════════════════════════"

if [[ "${WRITER_PROMOTION_FAILED}" == true ]]; then
  err ""
  err "Zeebe failover completed, but the Aurora writer never moved out of"
  err "${FAILED_AWS_REGION}. The surviving region is up and read-only."
  err "Check the promotion with:"
  err "  aws rds describe-global-clusters --global-cluster-identifier ${AURORA_GLOBAL_CLUSTER_ID}"
  exit 1
fi

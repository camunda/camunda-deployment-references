#!/usr/bin/env bash

###############################################################################
# Failback: ECS Dual-Region Fargate                                           #
#                                                                             #
# Restores balanced dual-region operation after ./failover.sh:                 #
#   1. Prints the topology before the change                                  #
#   2. Ensures the recovered region is an Aurora Global DB member             #
#   3. Scales the recovered region's ECS services back up, after wiping its   #
#      stale primary storage on EFS while the zone is absent                  #
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

# How long Step 6 waits for the re-added zone's brokers to join and take over
# partitions. A settle window, not a health budget.
LEADER_SETTLE_TIMEOUT="${LEADER_SETTLE_TIMEOUT:-180}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=SCRIPTDIR/zeebe_management_api.sh
. "${SCRIPT_DIR}/zeebe_management_api.sh"
# shellcheck source=SCRIPTDIR/aurora.sh
. "${SCRIPT_DIR}/aurora.sh"

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

# A failed read is not an empty global cluster: fail with the AWS error.
get_global_cluster_members() {
    aws rds describe-global-clusters \
        --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
        --query 'GlobalClusters[0].GlobalClusterMembers' \
        --output json --region "${RECOVERED_AWS_REGION}" || {
        err "Could not read the Aurora Global Database ${AURORA_GLOBAL_CLUSTER_ID}; see the AWS error above."
        return 1
    }
}

# Empties the recovered region's EFS primary storage with a one-off task that
# reuses the orchestration-cluster task definition's image, roles, network and
# EFS volume, so it needs no extra infrastructure.
WIPE_STARTED_BY=failback-wipe
wipe_primary_storage() {
    local service svc td_arn network counts leftover stopping wipe_def wipe_arn task_arn exit_code
    # shellcheck disable=SC2016 # backticks are a JMESPath literal
    service=$(aws ecs list-services --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --query 'serviceArns[?ends_with(@, `-orchestration-cluster`)] | [0]' --output text)
    svc=$(aws ecs describe-services --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --services "${service}" --query 'services[0]' --output json)
    td_arn=$(echo "${svc}" | jq -r '.taskDefinition')
    network=$(echo "${svc}" | jq -c '.networkConfiguration')
    # A zero runningCount alone allows a positive desiredCount with pending brokers.
    counts=$(echo "${svc}" | jq -r '"desired=\(.desiredCount) pending=\(.pendingCount) running=\(.runningCount)"')
    if [ "${counts}" != "desired=0 pending=0 running=0" ]; then
        err "${service##*/} is not scaled to 0 (${counts}); scale it to 0 before failback."
        exit 1
    fi
    # A wipe left running by an interrupted run must not delete data after this one.
    leftover=$(aws ecs list-tasks --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --started-by "${WIPE_STARTED_BY}" --query 'taskArns' --output json | jq -r '.[]')
    for task_arn in ${leftover}; do
        log "  Stopping wipe task ${task_arn} left by an earlier run..."
        aws ecs stop-task --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
            --task "${task_arn}" --no-cli-pager > /dev/null
    done
    # Tasks that are still stopping can hold the EFS volume open.
    stopping=$(aws ecs list-tasks --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --service-name "${service}" --desired-status STOPPED --query 'taskArns' --output json | jq -r '.[]')
    if [ -n "${leftover}${stopping}" ]; then
        log "  Waiting for earlier tasks to finish stopping..."
        # DescribeTasks, which the waiter calls, accepts at most 100 tasks.
        # shellcheck disable=SC2086 # one line per task ARN
        printf '%s\n' ${leftover} ${stopping} | xargs -n 100 aws ecs wait tasks-stopped \
            --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" --tasks
    fi

    log "  Wiping primary storage of ${RECOVERED_ZONE} (stale Raft state from before failover)..."
    wipe_def=$(aws ecs describe-task-definition --region "${RECOVERED_AWS_REGION}" \
        --task-definition "${td_arn}" --query 'taskDefinition' --output json | jq -c '
        {family: (.family + "-wipe"), taskRoleArn, executionRoleArn, networkMode,
         requiresCompatibilities, cpu, memory, runtimePlatform,
         volumes: [.volumes[] | select(.name == "camunda-volume")],
         containerDefinitions: [.containerDefinitions[] | select(.name == "orchestration-cluster")
           | {name, image, essential: true, logConfiguration, repositoryCredentials,
              mountPoints: [.mountPoints[] | select(.sourceVolume == "camunda-volume")],
              entryPoint: ["sh", "-c"],
              command: ["find /usr/local/camunda/data -mindepth 1 -delete"]}
           | with_entries(select(.value != null))]}
        | with_entries(select(.value != null))')
    wipe_arn=$(aws ecs register-task-definition --region "${RECOVERED_AWS_REGION}" \
        --cli-input-json "${wipe_def}" --query 'taskDefinition.taskDefinitionArn' --output text)
    task_arn=$(aws ecs run-task --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --launch-type FARGATE --task-definition "${wipe_arn}" --network-configuration "${network}" \
        --started-by "${WIPE_STARTED_BY}" --query 'tasks[0].taskArn' --output text)
    if ! aws ecs wait tasks-stopped --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" --tasks "${task_arn}"; then
        aws ecs stop-task --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
            --task "${task_arn}" --no-cli-pager > /dev/null || true
        err "Wipe task ${task_arn} did not stop in time; it was asked to stop. Re-run failback.sh."
        exit 1
    fi
    exit_code=$(aws ecs describe-tasks --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --tasks "${task_arn}" --query 'tasks[0].containers[0].exitCode' --output text)
    aws ecs deregister-task-definition --region "${RECOVERED_AWS_REGION}" \
        --task-definition "${wipe_arn}" --no-cli-pager > /dev/null
    if [ "${exit_code}" != "0" ]; then
        err "Wiping primary storage failed (exit code ${exit_code}); see task ${task_arn}."
        exit 1
    fi
    log "  Primary storage of ${RECOVERED_ZONE} wiped."
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

MEMBERS=$(get_global_cluster_members) || exit 1
MEMBER_COUNT=$(echo "${MEMBERS}" | jq 'length')

if [ "${MEMBER_COUNT}" = "0" ]; then
    err "Aurora Global Cluster ${AURORA_GLOBAL_CLUSTER_ID} not found or has no members."
    exit 1
fi

WRITER_ARN=$(echo "${MEMBERS}" | jq -r '.[] | select(.IsWriter == true) | .DBClusterArn')
log "Aurora writer is in: $(echo "${WRITER_ARN}" | awk -F':' '{print $4}')"

if [ "${MEMBER_COUNT}" = "1" ]; then
    log "Global DB has one member — re-attaching the ${RECOVERED_AWS_REGION} cluster."

    # The cluster has to exist and be standalone. An unplanned failover can
    # leave it detached but intact, which is the case this re-attaches; if it
    # was destroyed outright, Terraform has to recreate it first.
    RECOVERED_DB_ARN=$(aws rds describe-db-clusters \
        --region "${RECOVERED_AWS_REGION}" \
        --query "DBClusters[?contains(DBClusterIdentifier, '${RECOVERED_CLUSTER%-cluster}')].DBClusterArn" \
        --output text 2>/dev/null | head -1 || echo "")

    if [ -z "${RECOVERED_DB_ARN}" ]; then
        err "No Aurora cluster found in ${RECOVERED_AWS_REGION} to re-attach."
        err "If it was destroyed, recreate it first:"
        err "  terraform -chdir=${SCRIPT_DIR}/../terraform/infra apply"
        err "then re-run this script."
        exit 1
    fi

    RECOVERED_DB_ID="${RECOVERED_DB_ARN##*:}"
    log "  Found ${RECOVERED_DB_ID}; attaching to ${AURORA_GLOBAL_CLUSTER_ID}..."

    if [ "$DRY_RUN" = true ]; then
        log "  --dry-run given, not attaching."
    else
        aws rds create-db-cluster \
            --region "${RECOVERED_AWS_REGION}" \
            --global-cluster-identifier "${AURORA_GLOBAL_CLUSTER_ID}" \
            --db-cluster-identifier "${RECOVERED_DB_ID}" \
            --engine "${AURORA_ENGINE:?AURORA_ENGINE is required — source procedure/export_environment_prerequisites.sh}" \
            --no-cli-pager > /dev/null || {
                err "Failed to attach ${RECOVERED_DB_ID} to the global cluster."
                err "It may need to be recreated: terraform -chdir=${SCRIPT_DIR}/../terraform/infra apply"
                exit 1
            }
        wait_aurora_available "${RECOVERED_DB_ID}" "${RECOVERED_AWS_REGION}" 900
    fi
else
    log "Global DB has ${MEMBER_COUNT} members — nothing to re-attach."
fi

###############################################################################
# Step 2: Scale the recovered region back up                                  #
###############################################################################

log ""
log "=== Step 2: Scale up ECS services in ${RECOVERED_AWS_REGION} ==="

# How many brokers to expect once the zone is back. Read from the live cluster
# rather than assuming both zones are the same size: --brokers can recover an
# asymmetric zone, and a symmetric guess would fail an otherwise healthy
# failback. Measured before the scale-up, while only the surviving zone is up.
SURVIVING_TOPOLOGY=$(curl -sf --max-time 20 -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "http://${SURVIVING_ALB}/v2/topology" 2>/dev/null || echo "")
SURVIVING_BROKERS=$(echo "${SURVIVING_TOPOLOGY}" | jq --arg z "${RECOVERED_ZONE}" \
    '[.brokers[] | select(.brokerId | startswith($z + "_") | not)] | length' 2>/dev/null || echo "")

if ! [[ "${SURVIVING_BROKERS}" =~ ^[0-9]+$ ]] || [ "${SURVIVING_BROKERS}" -eq 0 ]; then
    err "Could not read the surviving broker count from http://${SURVIVING_ALB}/v2/topology."
    err "Failback cannot verify its own result without it; check the gateway and retry."
    exit 1
fi

TARGET_BROKERS=$(( SURVIVING_BROKERS + ZONE_BROKERS ))
log "  ${SURVIVING_BROKERS} broker(s) surviving, recovering ${ZONE_BROKERS} -> expecting ${TARGET_BROKERS}."

# A dry run must not restart the recovered region; only the Zones API call is
# exercised, with dryRun=true, further down.
if [ "$DRY_RUN" = true ]; then
    log "  --dry-run given, leaving ECS untouched."
    SERVICES=""
else
    SERVICES=$(aws ecs list-services \
        --region "${RECOVERED_AWS_REGION}" --cluster "${RECOVERED_CLUSTER}" \
        --query 'serviceArns[]' --output text 2>/dev/null || echo "")

    if [ -z "${SERVICES}" ]; then
        err "No ECS services found in ${RECOVERED_CLUSTER}."
        exit 1
    fi
fi

# The recovered brokers must rejoin with empty primary storage, as the
# multi-region operations guide requires ("its brokers start empty"). Their EFS
# still holds the Raft state from before the force-removal; from 8.11 on, a
# promotable member that installs a snapshot falls back to that stale stored
# configuration and PARTITION_PROMOTE never completes (#3766). Only wiped while
# the zone is absent from the partition distribution, so a re-run after a
# successful re-add cannot destroy live replicas.
if [ -n "${SERVICES}" ]; then
    if ! mgmt_tunnel_open "${SURVIVING_AWS_REGION}" "${SURVIVING_CLUSTER}" \
                          "${SURVIVING_PREFIX}" "${AWS_PROFILE:-}"; then
        err "Could not open a tunnel to the management API to check zone ${RECOVERED_ZONE}."
        exit 1
    fi
    PRE_ZONE_STATE=0
    mgmt_zone_present "${RECOVERED_ZONE}" || PRE_ZONE_STATE=$?
    mgmt_tunnel_close
    if [ "${PRE_ZONE_STATE}" -eq 2 ]; then
        err "Could not read the partition distribution; refusing to touch ${RECOVERED_ZONE} data."
        exit 1
    elif [ "${PRE_ZONE_STATE}" -eq 1 ]; then
        wipe_primary_storage
    else
        log "  Zone ${RECOVERED_ZONE} is still in the partition distribution — keeping its data."
    fi
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

ELAPSED=0
MAX_WAIT=900
if [ "$DRY_RUN" = true ]; then
    log "  --dry-run given, nothing was scaled up, so there is nothing to wait for."
    MAX_WAIT=0
fi
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

if [ "$DRY_RUN" != true ] && [ "${ELAPSED}" -ge "${MAX_WAIT}" ]; then
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

# `|| ZONE_STATE=$?` rather than a bare call: set -e would kill the script on a
# non-zero return before $? could be read, and 1 ("zone absent") is exactly the
# case that needs the re-add below.
ZONE_STATE=0
mgmt_zone_present "${RECOVERED_ZONE}" || ZONE_STATE=$?
if [ "${ZONE_STATE}" -eq 2 ]; then
    err "Could not read the partition distribution, so it is unknown whether"
    err "zone ${RECOVERED_ZONE} needs re-adding. Check: GET /actuator/cluster"
    exit 1
elif [ "${ZONE_STATE}" -eq 0 ]; then
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
    if ! BODY=$(mgmt_request POST "/actuator/cluster/zones/${RECOVERED_ZONE}${QUERY}" "${PAYLOAD}"); then
        err "Zone re-add rejected; see the response above."
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

# Reachable on a dry run when the zone was already present: nothing was scaled
# up, so asserting the full broker count here would fail on exactly the state
# someone runs --dry-run to inspect.
if [ "$DRY_RUN" = true ]; then
    mgmt_topology_summary "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
      "current state (dry run — nothing was changed)"
    log ""
    log "Dry run complete — no assertions run, because nothing was scaled up."
    exit 0
fi

mgmt_topology_summary "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
  "AFTER failback — ${RECOVERED_ZONE} restored"

IDLE_FILTER='[.brokers[] | select(.brokerId | startswith("'"${RECOVERED_ZONE}"'_"))
   | select((.partitions | length) == 0)] | length'
# Every partition must hold exactly one leader. `unique | length` counts a
# partition that reports two leaders once, so it passes a split brain.
LEADER_FILTER='[.brokers[].partitions[] | select(.role == "leader") | .partitionId]
   | group_by(.) | map(select(length == 1)) | length'
PARTITION_FILTER='[.brokers[].partitions[].partitionId] | unique | length'

FAILBACK_SETTLED="
  (.brokers | length) as \$brokers |
  (${PARTITION_FILTER}) as \$partitions |
  (${LEADER_FILTER}) as \$led |
  (${IDLE_FILTER}) as \$idle |
  \$brokers == ${TARGET_BROKERS} and \$idle == 0
    and \$partitions > 0 and \$led == \$partitions"

# Polled rather than read once: the re-added zone's tasks are still starting
# and taking over partitions, so the first answer is routinely short of the
# target even on a healthy failback.
if TOPOLOGY=$(mgmt_topology_settled "${SURVIVING_ALB}" "${ADMIN_USER}" "${ADMIN_PASS}" \
      "${LEADER_SETTLE_TIMEOUT}" "${FAILBACK_SETTLED}"); then
    SETTLED=true
else
    SETTLED=false
fi

# Counted on both paths: the closing summary reports them whatever happened,
# and under `set -u` a name left unset in the success branch aborts the script
# after the failback has already finished.
BROKERS=$(mgmt_topology_count "${TOPOLOGY}" '.brokers | length')
PARTITIONS=$(mgmt_topology_count "${TOPOLOGY}" "${PARTITION_FILTER}")
LEADERS=$(mgmt_topology_count "${TOPOLOGY}" "${LEADER_FILTER}")
IDLE=$(mgmt_topology_count "${TOPOLOGY}" "${IDLE_FILTER}")

if [ "${SETTLED}" = true ]; then
    log "✓ ${BROKERS} brokers, ${PARTITIONS} partitions, ${LEADERS} leaders, no idle brokers."
else
    if [ -z "${TOPOLOGY}" ]; then
        err "${SURVIVING_ALB} stopped answering within ${LEADER_SETTLE_TIMEOUT}s, so the failback could not be confirmed."
    elif [ "${BROKERS}" -ne "${TARGET_BROKERS}" ]; then
        err "Expected ${TARGET_BROKERS} brokers after ${LEADER_SETTLE_TIMEOUT}s, found ${BROKERS}."
    elif [ "${IDLE}" -ne 0 ]; then
        err "${IDLE} ${RECOVERED_ZONE} broker(s) host no partitions — the zone re-add did not take effect."
    else
        err "Only ${LEADERS} of ${PARTITIONS} partitions have exactly one leader after ${LEADER_SETTLE_TIMEOUT}s — not settled yet."
    fi
    err "Re-check with: ./verify_dual_region.sh"
    exit 1
fi

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

    if [ "$DRY_RUN" = true ]; then
        # Reachable on a dry run when the zone is already present, so this has
        # to be gated too: promoting the writer is not a validation step.
        log "  --dry-run given, not moving the writer."
    else
        # Safe on a rerun: a running switchover settles first, and a writer
        # already in place is left alone.
        if ! aurora_switch_to "${MEMBER_ARN}"; then
            err "Could not move the Aurora writer to ${RECOVERED_AWS_REGION}."
            exit 1
        fi
        log "Aurora writer is in ${RECOVERED_AWS_REGION}."
    fi
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
    --output text --region "${SURVIVING_AWS_REGION}" 2>/dev/null | awk -F':' '{print $4}')

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

#!/usr/bin/env bash
#
# verify-cluster-health.sh
#
# Checks the health of a Camunda cluster in two stages:
#
#   1. ECS Service Check (optional, requires --prefix):
#      Verifies that the ECS service has the desired number of tasks running
#      and all tasks are in RUNNING status. If the ECS service is not ready,
#      the topology check is skipped (no point checking topology if tasks
#      aren't all running).
#
#   2. Topology Check (always runs if ECS check passes):
#      Queries the v2 REST API (GET /v2/topology on port 8080) via the ALB
#      and evaluates broker/partition health.
#
# The /v2/topology endpoint returns cluster topology including broker info
# and per-partition health and role. See:
#   https://docs.camunda.io/docs/apis-tools/camunda-api-rest/specifications/get-topology/
#
# Response schema (JSON):
#   {
#     "gatewayVersion": "...",
#     "clusterSize": 3,
#     "partitionsCount": 3,
#     "replicationFactor": 3,
#     "lastCompletedChangeId": "1",
#     "brokers": [
#       {
#         "nodeId": 0,
#         "host": "...",
#         "port": 26501,
#         "version": "...",
#         "partitions": [
#           { "partitionId": 1, "role": "leader", "health": "healthy" }
#         ]
#       }
#     ]
#   }
#
# Returns a JSON report and exits with 0 if healthy, 1 if unhealthy.
#
# Prerequisites:
#   - The ALB endpoint must be reachable (benchmark deployed, ALB is public)
#   - curl and jq installed
#   - AWS CLI configured (only needed when --prefix is used for ECS checks)
#
# Usage:
#   ./experiments/verify-cluster-health.sh --endpoint <ALB_DNS>
#   ./experiments/verify-cluster-health.sh --endpoint my-alb.eu-west-1.elb.amazonaws.com --wait 60
#   ./experiments/verify-cluster-health.sh --endpoint <ALB_DNS> --prefix benchmark1
#
# Options:
#   --endpoint   ALB DNS name (required, port 8080 is appended automatically)
#   --prefix     Benchmark prefix (optional, e.g., benchmark1). When provided,
#                the script first checks that the ECS service has the desired
#                number of tasks running before checking the v2 topology.
#   --cluster    ECS cluster name (default: camunda-cluster)
#   --wait       Retry for up to N seconds if unhealthy (default: 0 = no retry)
#   --quiet      Only output the JSON report, no progress messages
#
# Authentication:
#   The reference architecture runs `basic` authentication with no unprotected
#   API, so /v2/topology answers 401 to an anonymous request and the cluster
#   looks unreachable. Export the credentials to authenticate:
#
#     export CAMUNDA_AUTH_USERNAME=admin
#     export CAMUNDA_AUTH_PASSWORD="$(aws secretsmanager get-secret-value \
#       --secret-id <prefix>-oc1-admin-user-password --query SecretString --output text)"
#
#   They are handed to curl through a config file on stdin rather than --user,
#   so the password never appears in argv or in `ps` output. Leave them unset
#   for a cluster that exposes the API without authentication.
#

set -euo pipefail

ENDPOINT=""
PREFIX=""
ECS_CLUSTER="${ECS_CLUSTER:-camunda-cluster}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
CAMUNDA_AUTH_USERNAME="${CAMUNDA_AUTH_USERNAME:-}"
CAMUNDA_AUTH_PASSWORD="${CAMUNDA_AUTH_PASSWORD:-}"
WAIT_SECONDS=0
QUIET=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --endpoint) ENDPOINT="$2";       shift 2 ;;
    --prefix)   PREFIX="$2";         shift 2 ;;
    --cluster)  ECS_CLUSTER="$2";    shift 2 ;;
    --wait)     WAIT_SECONDS="$2";   shift 2 ;;
    --quiet)    QUIET=true;          shift ;;
    -h|--help)
      echo "Usage: $0 --endpoint <ALB_DNS> [--prefix <BENCHMARK_PREFIX>] [--cluster <ECS_CLUSTER>] [--wait <SECONDS>] [--quiet]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${ENDPOINT}" ]]; then
  echo "ERROR: --endpoint is required."
  echo "Usage: $0 --endpoint <ALB_DNS_NAME>"
  exit 1
fi

# Strip trailing slash and any protocol prefix
ENDPOINT="${ENDPOINT%/}"
ENDPOINT="${ENDPOINT#http://}"
ENDPOINT="${ENDPOINT#https://}"

BASE_URL="http://${ENDPOINT}:80"

# Fetch a URL, authenticating when credentials are exported.
#
# The password is written to curl's stdin config rather than passed as --user,
# so it stays out of argv and out of `ps` for other users on the machine.
camunda_curl() {
    if [[ -n "${CAMUNDA_AUTH_USERNAME}" ]]; then
        printf 'user = "%s:%s"\n' "${CAMUNDA_AUTH_USERNAME}" "${CAMUNDA_AUTH_PASSWORD}" |
            curl -sf --max-time 10 --config - "$1" 2> /dev/null
    else
        curl -sf --max-time 10 "$1" 2> /dev/null
    fi
}

log() {
  if [[ "${QUIET}" != "true" ]]; then
    echo "$@"
  fi
}

# --- ECS service check function ---
# Verifies that the ECS service exists, has the desired number of tasks running,
# and all tasks are in RUNNING status.
# Returns JSON: { healthy: bool, service_name, desired_count, running_count,
#                  pending_count, tasks: [...], details }
check_ecs_service() {
  local service_name=""
  local desired_count=0
  local running_count=0
  local pending_count=0

  # Find the ECS service matching <prefix>-oc-*
  service_name=$(aws ecs list-services \
    --cluster "${ECS_CLUSTER}" \
    --query "serviceArns[?contains(@, '${PREFIX}-oc')]" \
    --output text \
    --region "${AWS_REGION}" 2>/dev/null | head -1 | xargs -I{} basename {} 2>/dev/null) || true

  if [[ -z "${service_name}" || "${service_name}" == "None" ]]; then
    echo '{}' | jq \
      --arg details "No ECS service found matching '${PREFIX}-oc' in cluster '${ECS_CLUSTER}'" \
      '{healthy: false, details: $details}'
    return 1
  fi

  # Get service details
  local service_json
  service_json=$(aws ecs describe-services \
    --cluster "${ECS_CLUSTER}" \
    --services "${service_name}" \
    --query "services[0]" \
    --output json \
    --region "${AWS_REGION}" 2>/dev/null) || true

  if [[ -z "${service_json}" || "${service_json}" == "null" ]]; then
    echo '{}' | jq \
      --arg details "Failed to describe ECS service '${service_name}'" \
      '{healthy: false, details: $details}'
    return 1
  fi

  desired_count=$(echo "${service_json}" | jq '.desiredCount // 0')
  running_count=$(echo "${service_json}" | jq '.runningCount // 0')
  pending_count=$(echo "${service_json}" | jq '.pendingCount // 0')

  # List running tasks
  local task_arns
  task_arns=$(aws ecs list-tasks \
    --cluster "${ECS_CLUSTER}" \
    --service-name "${service_name}" \
    --desired-status RUNNING \
    --query "taskArns[]" \
    --output json \
    --region "${AWS_REGION}" 2>/dev/null) || true

  local task_count
  task_count=$(echo "${task_arns:-[]}" | jq 'length')

  # Build task details if tasks exist
  local tasks_detail='[]'
  if [[ "${task_count}" -gt 0 ]]; then
    # shellcheck disable=SC2046 # word splitting is the point: --tasks takes one argument per task ARN
    tasks_detail=$(aws ecs describe-tasks \
      --cluster "${ECS_CLUSTER}" \
      --tasks $(echo "${task_arns}" | jq -r '.[]') \
      --query "tasks[*].{taskId:taskArn,az:availabilityZone,lastStatus:lastStatus,healthStatus:healthStatus,startedAt:startedAt}" \
      --output json \
      --region "${AWS_REGION}" 2>/dev/null) || tasks_detail='[]'

    # Shorten taskArn to just the task ID
    tasks_detail=$(echo "${tasks_detail}" | jq '[.[] | .taskId = (.taskId | split("/") | last)]')
  fi

  # Evaluate health
  local healthy=true
  local details=""

  if [[ "${running_count}" -lt "${desired_count}" ]]; then
    healthy=false
    details="${details}ECS service running ${running_count}/${desired_count} tasks. "
  fi

  if [[ "${pending_count}" -gt 0 ]]; then
    healthy=false
    details="${details}${pending_count} task(s) still pending. "
  fi

  # Check for tasks that are not RUNNING
  local not_running
  not_running=$(echo "${tasks_detail}" | jq '[.[] | select(.lastStatus != "RUNNING")] | length' 2>/dev/null || echo "0")
  if [[ "${not_running}" -gt 0 ]]; then
    healthy=false
    details="${details}${not_running} task(s) not in RUNNING status. "
  fi

  # Check if actual running task count matches desired
  if [[ "${task_count}" -lt "${desired_count}" ]]; then
    healthy=false
    details="${details}Only ${task_count} tasks found, expected ${desired_count}. "
  fi

  details="${details% }"

  if [[ "${healthy}" == "true" ]]; then
    details="ECS service healthy: ${running_count}/${desired_count} tasks running"
  fi

  local report
  report=$(jq -n \
    --argjson healthy "${healthy}" \
    --arg service_name "${service_name}" \
    --argjson desired_count "${desired_count}" \
    --argjson running_count "${running_count}" \
    --argjson pending_count "${pending_count}" \
    --argjson tasks "${tasks_detail}" \
    --arg details "${details}" \
    '{
      healthy: $healthy,
      service_name: $service_name,
      desired_count: $desired_count,
      running_count: $running_count,
      pending_count: $pending_count,
      tasks: $tasks,
      details: $details
    }')

  echo "${report}"

  if [[ "${healthy}" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# --- Health check function ---
# Queries GET /v2/topology and evaluates broker/partition health.
# Returns JSON: { healthy: bool, brokers_total, brokers_healthy,
#                  partitions_total, partitions_with_leader, details }
check_health() {
  local report='{}'
  local healthy=true
  local details=""

  # Query the v2 topology endpoint (single call replaces old actuator/health + actuator/cluster)
  local topology_response
  topology_response=$(camunda_curl "${BASE_URL}/v2/topology") || true

  if [[ -z "${topology_response}" ]]; then
    local hint="Topology API at ${BASE_URL}/v2/topology is not reachable"
    if [[ -z "${CAMUNDA_AUTH_USERNAME}" ]]; then
      hint="${hint} (no credentials exported; this reference runs basic auth, so an anonymous request gets 401 — see the header of this script)"
    fi
    report=$(echo '{}' | jq \
      --arg details "${hint}" \
      '{healthy: false, details: $details}')
    echo "${report}"
    return 1
  fi

  local brokers_count=0
  local healthy_brokers=0
  local partitions_with_leader=0
  local total_partitions=0
  local cluster_size=0
  local expected_partitions=0

  # Top-level cluster metadata
  cluster_size=$(echo "${topology_response}" | jq '.clusterSize // 0')
  expected_partitions=$(echo "${topology_response}" | jq '.partitionsCount // 0')

  # Count brokers returned
  brokers_count=$(echo "${topology_response}" | jq '[.brokers // [] | length] | .[0] // 0')

  # Count brokers where ALL partitions are healthy
  healthy_brokers=$(echo "${topology_response}" | jq '
    [.brokers // [] | .[] |
      select((.partitions // []) | all(.health == "healthy"))
    ] | length
  ')

  # Count unique partitions across all brokers
  total_partitions=$(echo "${topology_response}" | jq '
    [.brokers // [] | .[].partitions // [] | .[].partitionId] | unique | length
  ' 2>/dev/null || echo "0")

  # Count partitions that have at least one leader
  partitions_with_leader=$(echo "${topology_response}" | jq '
    [.brokers // [] | .[].partitions // [] | .[] | select(.role == "leader")] |
    group_by(.partitionId) |
    length
  ' 2>/dev/null || echo "0")

  # Evaluate health criteria
  if [[ "${brokers_count}" -lt "${cluster_size}" ]]; then
    healthy=false
    details="${details}Only ${brokers_count}/${cluster_size} brokers visible. "
  fi

  if [[ "${healthy_brokers}" -lt "${brokers_count}" ]]; then
    healthy=false
    details="${details}${healthy_brokers}/${brokers_count} brokers have all partitions healthy. "
  fi

  # Check for unhealthy or dead partitions
  local unhealthy_partitions
  unhealthy_partitions=$(echo "${topology_response}" | jq '
    [.brokers // [] | .[].partitions // [] | .[] | select(.health != "healthy")] | length
  ' 2>/dev/null || echo "0")

  if [[ "${unhealthy_partitions}" -gt 0 ]]; then
    healthy=false
    details="${details}${unhealthy_partitions} partition replica(s) are not healthy. "
  fi

  if [[ "${total_partitions}" -gt 0 && "${partitions_with_leader}" -lt "${total_partitions}" ]]; then
    healthy=false
    details="${details}${partitions_with_leader}/${total_partitions} partitions have a leader. "
  fi

  # Every count above is derived from the partitions the response actually
  # lists, so a partition missing from every broker would satisfy all of them.
  # partitionsCount is what the cluster says it should have.
  if [[ "${expected_partitions}" -gt 0 && "${total_partitions}" -lt "${expected_partitions}" ]]; then
    healthy=false
    details="${details}Only ${total_partitions}/${expected_partitions} partitions are present in the topology. "
  fi

  # Trim trailing space
  details="${details% }"

  if [[ "${healthy}" == "true" ]]; then
    details="All ${brokers_count} brokers healthy, ${partitions_with_leader}/${total_partitions} partitions have leaders"
  fi

  report=$(jq -n \
    --argjson healthy "${healthy}" \
    --argjson brokers_total "${brokers_count}" \
    --argjson brokers_healthy "${healthy_brokers}" \
    --argjson partitions_total "${total_partitions}" \
    --argjson partitions_with_leader "${partitions_with_leader}" \
    --argjson cluster_size "${cluster_size}" \
    --argjson expected_partitions "${expected_partitions}" \
    --arg details "${details}" \
    '{
      healthy: $healthy,
      cluster_size: $cluster_size,
      brokers_total: $brokers_total,
      brokers_healthy: $brokers_healthy,
      expected_partitions: $expected_partitions,
      partitions_total: $partitions_total,
      partitions_with_leader: $partitions_with_leader,
      details: $details
    }')

  echo "${report}"

  if [[ "${healthy}" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# --- Combined health check ---
# First checks ECS service health (if --prefix is provided), then topology.
# Returns merged JSON report.
run_health_check() {
  local ecs_result='null'
  local ecs_rc=0

  # Step 1: ECS service check (only if --prefix was provided)
  if [[ -n "${PREFIX}" ]]; then
    log "  Checking ECS service (${PREFIX}-oc)..."
    ecs_result=$(check_ecs_service) && ecs_rc=0 || ecs_rc=1

    if [[ ${ecs_rc} -ne 0 ]]; then
      local ecs_details
      ecs_details=$(echo "${ecs_result}" | jq -r '.details // "ECS service not ready"')
      log "  ECS service NOT ready: ${ecs_details}"

      # Return early — no point checking topology if ECS tasks aren't all running
      local report
      report=$(jq -n \
        --argjson ecs_service "${ecs_result}" \
        --arg details "ECS service is not ready — skipping topology check. ${ecs_details}" \
        '{
          healthy: false,
          ecs_service: $ecs_service,
          details: $details
        }')
      echo "${report}"
      return 1
    fi
    log "  ECS service is ready."
  fi

  # Step 2: Topology check
  log "  Checking cluster topology..."
  local topology_result
  local topology_rc
  topology_result=$(check_health) && topology_rc=0 || topology_rc=1

  # Merge results
  local overall_healthy
  if [[ ${topology_rc} -eq 0 ]]; then
    overall_healthy=true
  else
    overall_healthy=false
  fi

  local merged
  if [[ "${ecs_result}" != "null" ]]; then
    merged=$(echo "${topology_result}" | jq \
      --argjson ecs_service "${ecs_result}" \
      --argjson overall "${overall_healthy}" \
      '. + {ecs_service: $ecs_service, healthy: $overall}')
  else
    merged="${topology_result}"
  fi

  echo "${merged}"

  if [[ "${overall_healthy}" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# --- Main ---
log "=== Cluster Health Check ==="
log "Endpoint: ${BASE_URL}"
if [[ -n "${PREFIX}" ]]; then
  log "Benchmark: ${PREFIX}"
  log "ECS cluster: ${ECS_CLUSTER}"
fi
log ""

if [[ "${WAIT_SECONDS}" -gt 0 ]]; then
  log "Checking health (will retry for up to ${WAIT_SECONDS}s)..."
  DEADLINE=$(($(date +%s) + WAIT_SECONDS))
  ATTEMPT=1

  while true; do
    log "  Attempt ${ATTEMPT}..."
    RESULT=$(run_health_check) && RC=0 || RC=1

    if [[ ${RC} -eq 0 ]]; then
      log ""
      log "Cluster is HEALTHY"
      echo "${RESULT}"
      exit 0
    fi

    NOW=$(date +%s)
    if [[ ${NOW} -ge ${DEADLINE} ]]; then
      log ""
      log "Cluster is UNHEALTHY after ${WAIT_SECONDS}s"
      echo "${RESULT}"
      exit 1
    fi

    ATTEMPT=$((ATTEMPT + 1))
    sleep 10
  done
else
  log "Checking health..."
  RESULT=$(run_health_check) && RC=0 || RC=1
  log ""

  if [[ ${RC} -eq 0 ]]; then
    log "Cluster is HEALTHY"
  else
    log "Cluster is UNHEALTHY"
  fi

  echo "${RESULT}"
  exit "${RC}"
fi

#!/bin/bash

###############################################################################
# Zeebe management API helpers (sourced, not executed)                        #
#                                                                             #
# The management API lives on the broker's port 9600 and is deliberately not  #
# published through the ALB: terraform/infra/lb.tf gives the 9600 listener a   #
# fixed-response default and no forward rule, so /actuator/* is unreachable    #
# from outside the VPC. These helpers tunnel to it over the ECS Exec /         #
# Session Manager channel instead, which needs no bastion and no public       #
# exposure.                                                                   #
#                                                                             #
# Requires: awscli, the Session Manager plugin, jq, curl.                     #
#   macOS: brew install --cask session-manager-plugin                         #
#                                                                             #
# Usage:                                                                      #
#   . ./zeebe_management_api.sh                                               #
#   mgmt_tunnel_open "$REGION_1" "$CLUSTER_1" "${CLUSTER_NAME}-r1-oc"         #
#   mgmt_get /actuator/cluster                                                #
#   mgmt_tunnel_close        # or rely on the EXIT trap it installs           #
###############################################################################

MGMT_LOCAL_PORT="${MGMT_LOCAL_PORT:-9600}"
MGMT_URL="http://localhost:${MGMT_LOCAL_PORT}"
MGMT_SESSION_PID=""
# Every mgmt_get / mgmt_request runs inside a command substitution, and a
# subshell inherits the EXIT trap. Without an owner check the first such call
# would fire the trap and tear the tunnel down mid-script.
MGMT_OWNER_PID="$$"
MGMT_LAST_ARGS=()

mgmt_log() { echo "[$(date '+%H:%M:%S')] $*"; }
mgmt_err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

# mgmt_tunnel_close — terminate the port-forward if one is open.
mgmt_tunnel_close() {
    # Only the shell that opened the tunnel may close it; see MGMT_OWNER_PID.
    if [ "${BASHPID:-$$}" != "${MGMT_OWNER_PID}" ]; then
        return 0
    fi
    if [ -n "${MGMT_SESSION_PID}" ] && kill -0 "${MGMT_SESSION_PID}" 2>/dev/null; then
        kill "${MGMT_SESSION_PID}" 2>/dev/null || true
        wait "${MGMT_SESSION_PID}" 2>/dev/null || true
        mgmt_log "Closed management tunnel (pid ${MGMT_SESSION_PID})."
    fi
    MGMT_SESSION_PID=""
    rm -f "${MGMT_CODE_FILE}" 2>/dev/null || true
}

# mgmt_tunnel_open <aws_region> <ecs_cluster> <prefix> [aws_profile]
#
# Picks a running orchestration-cluster task and port-forwards its 9600 to
# localhost. `prefix` is the module prefix, e.g. "<cluster_name>-r1-oc"; the
# service is "<prefix>-orchestration-cluster" (modules/ecs/fargate/
# orchestration-cluster/ecs.tf:214).
mgmt_tunnel_open() {
    local region="$1" cluster="$2" prefix="$3" profile="${4:-}"
    # Kept so mgmt_tunnel_reopen can rebuild the tunnel unattended: a zone
    # change can drop the Session Manager channel part-way through, and the
    # management API guide warns the coordinator may relocate.
    MGMT_LAST_ARGS=("$region" "$cluster" "$prefix" "$profile")
    local profile_args=()
    [ -n "${profile}" ] && [ "${profile}" != "null" ] && profile_args=(--profile "${profile}")

    command -v session-manager-plugin >/dev/null 2>&1 || {
        mgmt_err "session-manager-plugin is not installed."
        mgmt_err "  macOS: brew install --cask session-manager-plugin"
        return 1
    }

    local service="${prefix}-orchestration-cluster"
    local task_arn task_id runtime_id

    task_arn=$(aws ecs list-tasks \
        --region "${region}" --cluster "${cluster}" \
        --service-name "${service}" --desired-status RUNNING \
        "${profile_args[@]}" \
        --query 'taskArns[0]' --output text 2>/dev/null || echo "None")

    if [ -z "${task_arn}" ] || [ "${task_arn}" = "None" ]; then
        mgmt_err "No RUNNING task in ${cluster}/${service} (${region})."
        return 1
    fi
    task_id="${task_arn##*/}"

    # shellcheck disable=SC2016  # JMESPath uses literal backticks, not shell command substitution
    runtime_id=$(aws ecs describe-tasks \
        --region "${region}" --cluster "${cluster}" --tasks "${task_id}" \
        "${profile_args[@]}" \
        --query 'tasks[0].containers[?name==`orchestration-cluster`].runtimeId' \
        --output text 2>/dev/null || echo "")

    if [ -z "${runtime_id}" ] || [ "${runtime_id}" = "None" ]; then
        mgmt_err "Could not resolve runtimeId for task ${task_id}."
        mgmt_err "ECS Exec must be enabled on the service (task_enable_execute_command = true)."
        return 1
    fi

    mgmt_log "Opening management tunnel to ${task_id} (localhost:${MGMT_LOCAL_PORT} -> 9600)..."
    aws ssm start-session \
        --region "${region}" "${profile_args[@]}" \
        --target "ecs:${cluster}_${task_id}_${runtime_id}" \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"9600\"],\"localPortNumber\":[\"${MGMT_LOCAL_PORT}\"]}" \
        > /dev/null 2>&1 &
    MGMT_SESSION_PID=$!

    MGMT_OWNER_PID="${BASHPID:-$$}"
    trap mgmt_tunnel_close EXIT

    local waited=0
    while [ "${waited}" -lt 40 ]; do
        if curl -sf --max-time 3 "${MGMT_URL}/actuator/cluster" -o /dev/null 2>/dev/null; then
            mgmt_log "Management tunnel is up."
            return 0
        fi
        if ! kill -0 "${MGMT_SESSION_PID}" 2>/dev/null; then
            mgmt_err "Session Manager exited while establishing the tunnel."
            MGMT_SESSION_PID=""
            return 1
        fi
        sleep 2
        waited=$((waited + 2))
    done

    mgmt_err "Management API did not answer on ${MGMT_URL} within ${waited}s."
    mgmt_tunnel_close
    return 1
}

# mgmt_get <path> — GET, prints the body.
mgmt_get() {
    curl -sf --max-time 8 "${MGMT_URL}$1" 2>/dev/null || echo ""
}

# mgmt_tunnel_alive — pid still running and the endpoint actually answers.
mgmt_tunnel_alive() {
    [ -n "${MGMT_SESSION_PID}" ] || return 1
    kill -0 "${MGMT_SESSION_PID}" 2>/dev/null || return 1
    curl -sf --max-time 5 "${MGMT_URL}/actuator/cluster" -o /dev/null 2>/dev/null
}

# mgmt_tunnel_reopen — rebuild the tunnel with the arguments last used.
mgmt_tunnel_reopen() {
    [ "${#MGMT_LAST_ARGS[@]}" -eq 4 ] || return 1
    mgmt_log "  Tunnel dropped — reopening..."
    mgmt_tunnel_close
    mgmt_tunnel_open "${MGMT_LAST_ARGS[0]}" "${MGMT_LAST_ARGS[1]}" \
                     "${MGMT_LAST_ARGS[2]}" "${MGMT_LAST_ARGS[3]}" >/dev/null 2>&1
}

# mgmt_request <method> <path> [json_body]
#
# Prints the response body. The HTTP status goes to a temp file rather than a
# shell variable: callers use it as BODY=$(mgmt_request ...), which runs in a
# subshell, so an assignment here would never reach them. Read the status with
# mgmt_last_code. Never fails the caller on a non-2xx, so the caller can report
# the body itself.
MGMT_CODE_FILE="${TMPDIR:-/tmp}/zeebe-mgmt-code.$$"
mgmt_request() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-s -w '\n%{http_code}' -X "${method}" --max-time 60
                -H 'Accept: application/json')
    [ -n "${body}" ] && args+=(-H 'Content-Type: application/json' -d "${body}")

    local out
    out=$(curl "${args[@]}" "${MGMT_URL}${path}" 2>/dev/null || true)
    printf '%s' "$(echo "${out}" | tail -1)" > "${MGMT_CODE_FILE}"
    echo "${out}" | sed '$d'
}

# mgmt_last_code — HTTP status of the most recent mgmt_request.
mgmt_last_code() {
    cat "${MGMT_CODE_FILE}" 2>/dev/null || echo ""
}

# mgmt_wait_change <change_id> [timeout_seconds]
#
# Zone operations are asynchronous. Poll GET /actuator/cluster/changes/{id}
# every five seconds until a terminal status, as the management API guide
# prescribes. Returns 0 only on COMPLETED.
mgmt_wait_change() {
    local change_id="$1" timeout="${2:-900}"
    local elapsed=0 status completed total

    while [ "${elapsed}" -lt "${timeout}" ]; do
        local body
        body=$(mgmt_get "/actuator/cluster/changes/${change_id}")

        if [ -n "${body}" ]; then
            status=$(echo "${body}" | jq -r '.status // empty' 2>/dev/null)
            completed=$(echo "${body}" | jq -r '[.completed // [] | length] | first' 2>/dev/null)
            total=$(echo "${body}" | jq -r '((.completed // [] | length) + (.pending // [] | length))' 2>/dev/null)

            case "${status}" in
                COMPLETED)
                    # The completed/pending arrays are empty once the change is
                    # done, so do not report a count here.
                    mgmt_log "  Change ${change_id} COMPLETED."
                    return 0 ;;
                FAILED|CANCELLED)
                    mgmt_err "Change ${change_id} ended as ${status}."
                    echo "${body}" | jq . 2>/dev/null || echo "${body}"
                    return 1 ;;
                IN_PROGRESS|*)
                    mgmt_log "  [${elapsed}s] Change ${change_id} ${status:-pending} (${completed:-0}/${total:-?})..." ;;
            esac
        else
            # Distinguish "tunnel died" from "cluster busy": only the former is
            # fixable here, and it is the common case during a forced removal.
            if ! mgmt_tunnel_alive; then
                mgmt_log "  [${elapsed}s] Management API unreachable via the tunnel."
                mgmt_tunnel_reopen || mgmt_log "  Reopen failed; will retry."
            else
                mgmt_log "  [${elapsed}s] Change not yet queryable (coordinator may be relocating)..."
            fi
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    mgmt_err "Timed out after ${timeout}s waiting for change ${change_id}."
    return 1
}

# mgmt_topology_summary <alb_endpoint> <user> <pass> [label]
#
# One-screen view of the cluster: brokers and partition replicas per zone,
# plus leader coverage. Printed before and after every failover step so the
# effect of the operation is visible rather than asserted.
mgmt_topology_summary() {
    local alb="$1" user="$2" pass="$3" label="${4:-}"
    local topo
    topo=$(curl -sf --max-time 20 -u "${user}:${pass}" "http://${alb}/v2/topology" 2>/dev/null || echo "")

    echo "-----------------------------------------------------------------"
    [ -n "${label}" ] && echo "  TOPOLOGY: ${label}"
    if [ -z "${topo}" ]; then
        echo "  unreachable via ${alb}"
        echo "-----------------------------------------------------------------"
        return 1
    fi

    # 8.10 reports partition roles in lower case ("leader"/"follower").
    echo "${topo}" | jq -r '
      (.brokers | length) as $b |
      ([.brokers[].partitions[]] | length) as $replicas |
      ([.brokers[].partitions[] | select(.role == "leader")] | length) as $leaders |
      ([.brokers[].partitions[].partitionId] | unique | length) as $partitions |
      "  brokers=\($b)  partitions=\($partitions)  replicas=\($replicas)  leaders=\($leaders)"
      + "  clusterSize=\(.clusterSize)  replicationFactor=\(.replicationFactor)",
      "  per zone:",
      ([.brokers[] | {zone: (.brokerId | split("_")[0]),
                      leaders: [.partitions[] | select(.role == "leader")] | length,
                      replicas: (.partitions | length)}]
       | group_by(.zone)
       | map("    \(.[0].zone): brokers=\(length) replicas=\(map(.replicas) | add) leaders=\(map(.leaders) | add)")
       | .[])
    '
    echo "-----------------------------------------------------------------"
}

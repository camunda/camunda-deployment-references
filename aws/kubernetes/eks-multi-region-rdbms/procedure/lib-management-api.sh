#!/bin/bash
# Shared helpers for the Orchestration Cluster management API (port 9600).
#
# Source this file; it defines functions rather than running anything:
#
#   . ./lib-management-api.sh
#
# Every call opens a short-lived port-forward. Long-lived tunnels break when a
# broker restarts, which happens routinely while a cluster change is applied.

# shellcheck shell=bash

MANAGEMENT_LOCAL_PORT="${MANAGEMENT_LOCAL_PORT:-9600}"
GATEWAY_LOCAL_PORT="${GATEWAY_LOCAL_PORT:-8080}"

# Status of the last camunda::_request, for callers that distinguish "not ready
# yet" from "wrong". A cold gateway answers 401 before its security layer is up.
CAMUNDA_LAST_STATUS=""

# camunda::zone_name <slot> -> the zone a region slot belongs to.
camunda::zone_name() {
    local slot="$1"
    local zone_names
    read -r -a zone_names <<<"${CAMUNDA_ZONE_NAMES:?CAMUNDA_ZONE_NAMES must be set, source export-terraform-outputs.sh}"

    local zone="${zone_names[$slot]:-}"
    if [ -z "$zone" ]; then
        echo "ERROR: CAMUNDA_ZONE_NAMES has no entry for region slot $slot." >&2
        return 1
    fi
    echo "$zone"
}

# camunda::survivor_context <excluded-slot> -> the kubectl context of any active
# region other than the excluded one, to drive the management API from.
camunda::survivor_context() {
    local excluded="$1"
    local contexts
    read -r -a contexts <<<"${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"

    local i
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        if [ "$i" -ne "$excluded" ]; then
            echo "${contexts[$i]}"
            return 0
        fi
    done

    echo "ERROR: no active region left besides slot $excluded." >&2
    return 1
}

# camunda::use_surviving_region <excluded-slot>
#
# Points the AWS CLI at a region that is still up, when nothing else has.
#
# The RDS calls in failover.sh and failback.sh carry no `--region`, so they take
# the CLI default. During a regional outage that default is the worst possible
# choice if it happens to be the region that just went: the control-plane calls
# meant to recover from the outage fail because of it. An explicit setting is
# left alone, and only pointed out.
camunda::use_surviving_region() {
    local excluded="$1"
    local regions
    read -r -a regions <<<"${AWS_REGIONS:?AWS_REGIONS must be set, source export_environment_prerequisites.sh}"

    local lost="${regions[$excluded]:-}"

    if [ -n "${AWS_REGION:-}" ] || [ -n "${AWS_DEFAULT_REGION:-}" ]; then
        local current="${AWS_REGION:-$AWS_DEFAULT_REGION}"
        if [ -n "$lost" ] && [ "$current" = "$lost" ]; then
            echo "WARNING: the AWS CLI is pointed at $current, the region being failed over." >&2
            echo "         Its control plane may be exactly what is unavailable. Export" >&2
            echo "         AWS_REGION to a surviving region if these calls hang or fail." >&2
        fi
        return 0
    fi

    local i
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        if [ "$i" -ne "$excluded" ]; then
            export AWS_REGION="${regions[$i]}"
            echo "    AWS CLI region: $AWS_REGION (surviving slot $i; neither AWS_REGION nor AWS_DEFAULT_REGION was set)"
            return 0
        fi
    done

    echo "ERROR: no surviving region left to drive the AWS CLI from." >&2
    return 1
}

# camunda::region_node_ids <slot> -> space-separated broker IDs of a slot.
#
# Zone-aware brokers are addressed by the composite ID `<zone>_<index>`, where
# the index runs from 0 to numberOfBrokers-1 inside each zone. That is what the
# management API answers with, and what it expects back:
#
#   {"brokers":[{"id":"zurich_0", ...},{"id":"zurich_1", ...}]}
#
# check-cluster-topology.sh takes the same format apart to attribute brokers to
# zones; the two have to agree on the separator.
camunda::region_node_ids() {
    local slot="$1"
    local zone
    zone="$(camunda::zone_name "$slot")" || return 1

    local ids=()
    local index
    for ((index = 0; index < CAMUNDA_BROKERS_PER_REGION; index++)); do
        ids+=("${zone}_${index}")
    done
    echo "${ids[@]}"
}

# camunda::_request <context> <local-port> <remote-port> <auth> <method> <path> [body]
#
# The one place that talks HTTP to a gateway. Prints the response body, sets
# CAMUNDA_LAST_STATUS to the HTTP status, and returns non-zero outside 2xx.
#
# CAMUNDA_LAST_STATUS is only visible to a caller that does NOT capture the body
# through `$(...)`: command substitution runs the function in a subshell, and the
# assignment dies with it. Redirect the body to a file instead:
#
#   camunda::gateway_get "$ctx" /v2/topology >"$OUTPUT_FILE" || echo "$CAMUNDA_LAST_STATUS"
#
# The tunnel is opened and closed per call on purpose. A long-lived one dies
# whenever a broker restarts, which is routine while a cluster change is applied
# and constant right after a region is lost, and every later request through it
# then fails in a way that reads as "the cluster is gone" rather than "the tunnel
# is gone".
#
# The status is not decoration either. A rejected change otherwise reads exactly
# like an accepted one, and the caller waits out its whole timeout polling for
# something the cluster never took:
#
#   {"message":"Changing the replication factor is not supported on zone-aware clusters."}
#     waiting for the cluster change to complete (last status: unknown) ...
camunda::_request() {
    local context="$1" local_port="$2" remote_port="$3" auth="$4"
    local method="$5" path="$6" body="${7:-}"

    kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" \
        port-forward "svc/${CAMUNDA_RELEASE_NAME}-zeebe-gateway" \
        "${local_port}:${remote_port}" >/dev/null 2>&1 &
    local pid=$!
    sleep 3

    # Bounded, because the callers are polling loops with their own deadlines and
    # a port-forward that half-opens rather than dies makes curl wait forever,
    # which is exactly the case those deadlines exist for. 000 on expiry reads
    # the same as any other unanswered call, so the loops retry as they already do.
    local curl_args=(-sS -w '\n%{http_code}' -X "$method"
        --connect-timeout "${CAMUNDA_API_CONNECT_TIMEOUT:-5}"
        --max-time "${CAMUNDA_API_MAX_TIME:-30}")
    [ -n "$auth" ] && curl_args+=(-u "$auth")
    [ -n "$body" ] && curl_args+=(-H 'Content-Type: application/json' -d "$body")

    local response
    response="$(curl "${curl_args[@]}" "http://localhost:${local_port}${path}")" || true

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    # `-w` appends the status on its own line, so the body is everything before
    # it. curl reports 000 when it never got an answer at all.
    CAMUNDA_LAST_STATUS="${response##*$'\n'}"
    CAMUNDA_LAST_STATUS="${CAMUNDA_LAST_STATUS:-000}"
    local payload="${response%$'\n'*}"

    echo "$payload"

    case "$CAMUNDA_LAST_STATUS" in
    2*) return 0 ;;
    *)
        echo "ERROR: $method $path answered HTTP $CAMUNDA_LAST_STATUS" >&2
        echo "$payload" >&2
        return 1
        ;;
    esac
}

# camunda::management <context> <method> <path> [body]
#
# Cluster management API, port 9600, no authentication.
camunda::management() {
    local context="$1" method="$2" path="$3" body="${4:-}"
    camunda::_request "$context" "$MANAGEMENT_LOCAL_PORT" 9600 "" \
        "$method" "$path" "$body"
}

# camunda::gateway_get <context> <path>
#
# Orchestration Cluster REST API, port 8080, basic authentication. Used to read
# `/v2/topology`, which is the list of brokers that actually registered, as
# opposed to the membership `/actuator/cluster` reports from the configuration.
camunda::gateway_get() {
    local context="$1" path="$2"
    camunda::_request "$context" "$GATEWAY_LOCAL_PORT" 8080 \
        "${CAMUNDA_BASIC_AUTH_USER:-demo}:${CAMUNDA_BASIC_AUTH_PASSWORD:-demo}" \
        GET "$path"
}

# camunda::wait_for_cluster_change <context> [timeout_seconds]
#
# Polls GET /actuator/cluster until no change is pending and the last change
# reports COMPLETED.
camunda::wait_for_cluster_change() {
    local context="$1"
    local timeout="${2:-900}"
    local deadline=$((SECONDS + timeout))

    while true; do
        local cluster
        # A failed poll is not a failed change: brokers restart while one is
        # applied, and the gateway is briefly unreachable. Retry until the
        # deadline instead.
        cluster="$(camunda::management "$context" GET /actuator/cluster 2>/dev/null)" || cluster=""

        local pending
        pending="$(echo "$cluster" | jq -r '.pendingChange // empty' 2>/dev/null || true)"
        local status
        status="$(echo "$cluster" | jq -r '.lastChange.status // empty' 2>/dev/null || true)"

        if [ -z "$pending" ] && [ "$status" = "COMPLETED" ]; then
            echo "Cluster change completed."
            return 0
        fi

        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: cluster change did not complete within ${timeout}s." >&2
            echo "$cluster" >&2
            return 1
        fi

        echo "  waiting for the cluster change to complete (last status: ${status:-unknown}) ..."
        sleep 15
    done
}

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

# camunda::management <context> <method> <path> [body]
#
# Performs a request against the management API of a region's gateway, prints
# the response body, and returns non-zero on any status outside 2xx.
#
# The status is not decoration. A rejected change otherwise reads exactly like an
# accepted one, and the caller goes on to wait out its whole timeout polling for
# something the cluster never took:
#
#   {"message":"Changing the replication factor is not supported on zone-aware clusters."}
#     waiting for the cluster change to complete (last status: unknown) ...
#     waiting for the cluster change to complete (last status: unknown) ...
camunda::management() {
    local context="$1"
    local method="$2"
    local path="$3"
    local body="${4:-}"

    kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" \
        port-forward "svc/${CAMUNDA_RELEASE_NAME}-zeebe-gateway" \
        "${MANAGEMENT_LOCAL_PORT}:9600" >/dev/null 2>&1 &
    local pid=$!
    # Give the tunnel time to establish; the port-forward is torn down below
    # even when curl fails, so a stray process cannot leak.
    sleep 3

    local curl_args=(-sS -w '\n%{http_code}' -X "$method")
    if [ -n "$body" ]; then
        curl_args+=(-H 'Content-Type: application/json' -d "$body")
    fi

    local response
    response="$(curl "${curl_args[@]}" "http://localhost:${MANAGEMENT_LOCAL_PORT}${path}")" || true

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    # `-w` appends the status on its own line, so the body is everything before
    # it. curl reports 000 when it never got an answer at all.
    local status="${response##*$'\n'}"
    local payload="${response%$'\n'*}"

    echo "$payload"

    case "$status" in
    2*) return 0 ;;
    *)
        echo "ERROR: $method $path answered HTTP ${status:-000}" >&2
        echo "$payload" >&2
        return 1
        ;;
    esac
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

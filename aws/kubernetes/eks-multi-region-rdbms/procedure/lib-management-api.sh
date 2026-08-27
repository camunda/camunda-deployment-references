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

# camunda::region_node_ids <slot> -> space-separated broker IDs of a slot.
#
# Zone-aware brokers are addressed by the composite ID `<zone>_<index>`, where
# the index runs from 0 to numberOfBrokers-1 inside each zone. That is what the
# management API answers with, and what it expects back:
#
#   {"brokers":[{"id":"zurich_0", ...},{"id":"zurich_1", ...}]}
camunda::region_node_ids() {
    local slot="$1"
    local zone_names
    read -r -a zone_names <<<"${CAMUNDA_ZONE_NAMES:?CAMUNDA_ZONE_NAMES must be set, source export-terraform-outputs.sh}"

    local zone="${zone_names[$slot]:-}"
    if [ -z "$zone" ]; then
        echo "ERROR: CAMUNDA_ZONE_NAMES has no entry for region slot $slot." >&2
        return 1
    fi

    local ids=()
    local index
    for ((index = 0; index < CAMUNDA_BROKERS_PER_REGION; index++)); do
        ids+=("${zone}_${index}")
    done
    echo "${ids[@]}"
}

# camunda::management <context> <method> <path> [body]
#
# Performs a request against the management API of a region's gateway.
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

    local response
    if [ -n "$body" ]; then
        response="$(curl -sS -X "$method" \
            -H 'Content-Type: application/json' \
            -d "$body" \
            "http://localhost:${MANAGEMENT_LOCAL_PORT}${path}")" || true
    else
        response="$(curl -sS -X "$method" \
            "http://localhost:${MANAGEMENT_LOCAL_PORT}${path}")" || true
    fi

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    echo "$response"
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
        cluster="$(camunda::management "$context" GET /actuator/cluster)"

        local pending
        pending="$(echo "$cluster" | jq -r '.pendingChange // empty')"
        local status
        status="$(echo "$cluster" | jq -r '.lastChange.status // empty')"

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

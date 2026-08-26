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

# camunda::registered_broker_count <context> -> number of brokers the gateway
# lists, or 0 when it cannot be reached.
#
# This is the count of brokers that actually registered, which is not what
# `GET /actuator/cluster` reports: that one answers with the CONFIGURED
# membership, so a broker appears there as soon as the partition layout names
# it, whether or not the process exists. Waiting on the configured list
# therefore succeeds instantly and says nothing.
camunda::registered_broker_count() {
    local context="$1"

    kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" \
        port-forward "svc/${CAMUNDA_RELEASE_NAME}-zeebe-gateway" \
        "${GATEWAY_LOCAL_PORT}:8080" >/dev/null 2>&1 &
    local pid=$!
    sleep 3

    local response
    response="$(curl -sS \
        -u "${CAMUNDA_BASIC_AUTH_USER:-demo}:${CAMUNDA_BASIC_AUTH_PASSWORD:-demo}" \
        "http://localhost:${GATEWAY_LOCAL_PORT}/v2/topology" 2>/dev/null)" || true

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    echo "$response" | jq -r '.brokers | length' 2>/dev/null || echo 0
}

# camunda::region_node_ids <slot> -> space-separated broker node IDs of a slot.
#
# The Helm chart derives node IDs as `ordinal * regionSlots + regionId`, so the
# brokers of a slot are that slot's residue class modulo the number of slots.
camunda::region_node_ids() {
    local slot="$1"
    local ids=()
    local ordinal
    for ((ordinal = 0; ordinal < CAMUNDA_BROKERS_PER_REGION; ordinal++)); do
        ids+=($((ordinal * CAMUNDA_REGION_SLOTS + slot)))
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

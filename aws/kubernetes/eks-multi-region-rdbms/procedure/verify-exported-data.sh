#!/bin/bash
# Asserts that a database writer failover loses no exported data.
#
#   ./verify-exported-data.sh record <state-file>
#   ./verify-exported-data.sh verify <state-file> <lost-region-slot>
#
# The architecture's acceptance criterion is that secondary storage survives a
# writer promotion without data loss. Every other check in this suite proves
# continuity: brokers keep a quorum, the gateway keeps answering. None of them
# would notice exported rows disappearing, because an empty secondary storage
# answers a topology query exactly like a full one.
#
# So this script writes a known set of process instances through the exporter
# before the region is lost, and looks for the same set afterwards. The read
# path is the product's own: /v2/process-instances/search is served from
# secondary storage, so a row the promoted database never received, and that
# Zeebe did not replay, is a row this search cannot return.
#
# This is a lower bound on data loss, not a measure of it. It cannot see records
# exported between the last recorded instance and the outage, which is exactly
# the window asynchronous replication monitoring exists to close. Widening it
# means writing continuously through the failover, which needs a load generator
# this suite does not have.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_RESOURCE="${SCRIPT_DIR}/resources/data-loss-probe.bpmn"
PROBE_PROCESS_ID="multiRegionDataLossProbe"

: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"

PROBE_INSTANCES="${PROBE_INSTANCES:-10}"
PROBE_EXPORT_TIMEOUT_SECONDS="${PROBE_EXPORT_TIMEOUT_SECONDS:-600}"

# shellcheck source=SCRIPTDIR/lib-management-api.sh
. "${SCRIPT_DIR}/lib-management-api.sh"

MODE="${1:-}"
STATE_FILE="${2:-}"

if [ -z "$MODE" ] || [ -z "$STATE_FILE" ]; then
    echo "usage: $0 record <state-file>" >&2
    echo "       $0 verify <state-file> <lost-region-slot>" >&2
    exit 1
fi

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

# probe::search_keys <context> -> the process instance keys secondary storage
# currently holds for the probe process, one per line.
probe::search_keys() {
    local context="$1"
    local body
    body="$(printf '{"filter":{"processDefinitionId":"%s"},"page":{"limit":1000}}' "$PROBE_PROCESS_ID")"

    camunda::gateway_post "$context" /v2/process-instances/search "$body" >"$OUTPUT_FILE" 2>/dev/null || return 1
    jq -r '.items[]?.processInstanceKey // empty' "$OUTPUT_FILE" 2>/dev/null || true
}

probe::record() {
    local context
    read -r -a contexts <<<"$CLUSTER_CONTEXTS"
    context="${contexts[0]}"

    echo "--> Deploying the probe process from $context"
    camunda::gateway_upload "$context" /v2/deployments "$PROBE_RESOURCE" >"$OUTPUT_FILE"

    local definition_key
    definition_key="$(jq -r '.deployments[]?.processDefinition.processDefinitionKey // empty' "$OUTPUT_FILE" | head -1)"
    if [ -z "$definition_key" ]; then
        echo "ERROR: the deployment response carried no process definition key." >&2
        cat "$OUTPUT_FILE" >&2
        exit 1
    fi
    echo "    process definition key $definition_key"

    echo "--> Starting $PROBE_INSTANCES process instance(s)"
    local expected=()
    local i
    for ((i = 0; i < PROBE_INSTANCES; i++)); do
        local response key
        response="$(camunda::gateway_post "$context" /v2/process-instances \
            "$(printf '{"processDefinitionKey":"%s"}' "$definition_key")")"
        key="$(echo "$response" | jq -r '.processInstanceKey // empty')"
        if [ -z "$key" ]; then
            echo "ERROR: starting instance $((i + 1)) returned no key." >&2
            echo "$response" >&2
            exit 1
        fi
        expected+=("$key")
    done
    echo "    started: ${expected[*]}"

    # Exporting is asynchronous, and with replication monitoring enabled a record
    # is only acknowledged once the database reports it replicated. Waiting for
    # every key to be searchable is therefore also the proof that the baseline
    # itself reached the standby, which is what makes the later comparison mean
    # anything.
    echo "--> Waiting for all $PROBE_INSTANCES instance(s) to reach secondary storage"
    local deadline=$((SECONDS + PROBE_EXPORT_TIMEOUT_SECONDS))
    while true; do
        local visible found=0
        visible="$(probe::search_keys "$context" || true)"

        local key
        for key in "${expected[@]}"; do
            if grep -qx "$key" <<<"$visible"; then
                found=$((found + 1))
            fi
        done

        if [ "$found" -eq "$PROBE_INSTANCES" ]; then
            echo "    all $PROBE_INSTANCES instance(s) are searchable."
            break
        fi

        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: only $found/$PROBE_INSTANCES instance(s) reached secondary storage within ${PROBE_EXPORT_TIMEOUT_SECONDS}s." >&2
            echo "       The baseline is incomplete, so a later comparison would prove nothing." >&2
            exit 1
        fi

        echo "    $found/$PROBE_INSTANCES searchable, waiting ..."
        sleep 10
    done

    printf '%s\n' "${expected[@]}" >"$STATE_FILE"
    echo
    echo "Recorded $PROBE_INSTANCES exported process instance(s) in $STATE_FILE."
}

probe::verify() {
    local lost_slot="$1"
    camunda::require_slot "$lost_slot" "lost-region-slot"

    if [ ! -s "$STATE_FILE" ]; then
        echo "ERROR: $STATE_FILE is missing or empty; run 'record' before the region loss." >&2
        exit 1
    fi

    local expected=()
    mapfile -t expected <"$STATE_FILE"

    local context
    context="$(camunda::survivor_context "$lost_slot")"
    echo "--> Reading secondary storage from $context after the writer promotion"

    # The promoted member and the gateway both settle at their own pace, so a
    # single failed read is not a lost record. Retry until the deadline and only
    # then compare, otherwise this reports data loss for a database that was
    # still coming up.
    local deadline=$((SECONDS + PROBE_EXPORT_TIMEOUT_SECONDS))
    local visible=""
    while true; do
        visible="$(probe::search_keys "$context" || true)"
        [ -n "$visible" ] && break

        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: secondary storage returned no probe instance at all within ${PROBE_EXPORT_TIMEOUT_SECONDS}s (last status: ${CAMUNDA_LAST_STATUS:-unknown})." >&2
            exit 1
        fi

        echo "    no rows yet, waiting ..."
        sleep 10
    done

    local missing=()
    local key
    for key in "${expected[@]}"; do
        grep -qx "$key" <<<"$visible" || missing+=("$key")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "ERROR: ${#missing[@]} of ${#expected[@]} exported process instance(s) are gone from secondary storage." >&2
        echo "       Missing keys: ${missing[*]}" >&2
        echo "       The writer promotion lost exported data. Check that" >&2
        echo "       camunda.data.secondary-storage.rdbms.async-replication is enabled and that the" >&2
        echo "       broker volume held the retained log segments needed to replay." >&2
        exit 1
    fi

    echo
    echo "All ${#expected[@]} exported process instance(s) survived the writer promotion."
}

case "$MODE" in
record)
    probe::record
    ;;
verify)
    probe::verify "${3:?usage: $0 verify <state-file> <lost-region-slot>}"
    ;;
*)
    echo "ERROR: unknown mode '$MODE'; expected 'record' or 'verify'." >&2
    exit 1
    ;;
esac

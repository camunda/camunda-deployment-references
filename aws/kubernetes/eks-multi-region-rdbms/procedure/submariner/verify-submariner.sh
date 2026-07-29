#!/bin/bash
set -euo pipefail

# Waits until every cluster reports N-1 established Submariner connections,
# where N is the number of active regions. Submariner builds a full mesh of
# tunnels, so each cluster connects to every other one.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

TIMEOUT_SECONDS="${SUBMARINER_VERIFY_TIMEOUT_SECONDS:-900}"
POLL_INTERVAL_SECONDS="${SUBMARINER_VERIFY_POLL_INTERVAL_SECONDS:-15}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
expected_connections=$((CAMUNDA_ACTIVE_REGIONS - 1))

deadline=$((SECONDS + TIMEOUT_SECONDS))

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    echo "Verifying Submariner on $context (expecting $expected_connections established connection(s))"

    while true; do
        status="$(subctl show all --contexts "$context" 2>&1 || true)"

        if echo "$status" | grep -q "All connections ($expected_connections) are established"; then
            echo "  OK"
            break
        fi

        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: Submariner did not converge on $context within ${TIMEOUT_SECONDS}s." >&2
            echo "$status" >&2
            exit 1
        fi

        echo "  not converged yet, retrying in ${POLL_INTERVAL_SECONDS}s ..."
        sleep "$POLL_INTERVAL_SECONDS"
    done
done

echo
echo "Submariner mesh is established across $CAMUNDA_ACTIVE_REGIONS clusters."

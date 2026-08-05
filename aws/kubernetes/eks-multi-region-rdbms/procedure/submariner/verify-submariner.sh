#!/bin/bash
set -euo pipefail

# Waits until Submariner service discovery is functional in every active
# cluster.
#
# What is NOT checked, on purpose: established tunnels. Submariner is deployed
# with the service-discovery component only, so `subctl show connections` is
# empty by design and waiting on it would hang forever. Cross-region reachability
# is the Transit Gateway's job and is proven separately by
# ../verify-cross-region-connectivity.sh.
#
# What is checked:
#   1. the Lighthouse agent and DNS pods are Ready, so exports can propagate and
#      clusterset names can be answered;
#   2. every cluster is registered in the broker, which is what makes the other
#      clusters able to resolve its exported services.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export_environment_prerequisites.sh}"

TIMEOUT_SECONDS="${SUBMARINER_VERIFY_TIMEOUT_SECONDS:-600}"
POLL_INTERVAL_SECONDS="${SUBMARINER_VERIFY_POLL_INTERVAL_SECONDS:-15}"
SUBMARINER_NAMESPACE="${SUBMARINER_NAMESPACE:-submariner-operator}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
read -r -a cluster_ids <<<"$SUBMARINER_CLUSTER_IDS"

###############################################################################
# 1. Lighthouse is running in every cluster                                   #
###############################################################################

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    echo "Waiting for Lighthouse on $context"

    for deployment in submariner-lighthouse-agent submariner-lighthouse-coredns; do
        if ! kubectl --context "$context" -n "$SUBMARINER_NAMESPACE" \
            rollout status "deployment/$deployment" --timeout="${TIMEOUT_SECONDS}s"; then
            echo "ERROR: $deployment did not become available on $context." >&2
            kubectl --context "$context" -n "$SUBMARINER_NAMESPACE" get pods -o wide >&2 || true
            exit 1
        fi
    done
done

###############################################################################
# 2. Every cluster is registered in the broker                                #
#                                                                             #
# The Cluster resources are synced to each joined cluster, so any context can  #
# be asked. A missing entry means a join did not complete, and the symptom      #
# would otherwise surface much later as an unresolvable clusterset name.       #
###############################################################################

echo
echo "Waiting for all $CAMUNDA_ACTIVE_REGIONS clusters to be registered"

deadline=$((SECONDS + TIMEOUT_SECONDS))
while true; do
    registered="$(kubectl --context "${contexts[0]}" -n "$SUBMARINER_NAMESPACE" \
        get clusters.submariner.io -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort -u)"

    missing=""
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        if ! printf '%s\n' "$registered" | grep -qx "${cluster_ids[$i]}"; then
            missing="${missing:+$missing }${cluster_ids[$i]}"
        fi
    done

    if [ -z "$missing" ]; then
        echo "  registered: $(printf '%s' "$registered" | tr '\n' ' ')"
        break
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ERROR: cluster(s) not registered in the broker after ${TIMEOUT_SECONDS}s: $missing" >&2
        echo "       Re-run ./join-clusters.sh for the missing slot(s)." >&2
        exit 1
    fi

    echo "  still missing: $missing"
    sleep "$POLL_INTERVAL_SECONDS"
done

echo
echo "Submariner service discovery is ready across $CAMUNDA_ACTIVE_REGIONS clusters."
echo "Cross-region reachability is provided by the Transit Gateway; prove it with"
echo "../verify-cross-region-connectivity.sh."

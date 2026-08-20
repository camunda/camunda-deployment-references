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
#   2. the clusterset.local zone is wired into the cluster's own resolver.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"

TIMEOUT_SECONDS="${SUBMARINER_VERIFY_TIMEOUT_SECONDS:-600}"
SUBMARINER_NAMESPACE="${SUBMARINER_NAMESPACE:-submariner-operator}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

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
# 2. Clusterset DNS is wired into the cluster's own resolver                  #
#                                                                             #
# `subctl join` patches CoreDNS to forward the clusterset.local zone to the   #
# Lighthouse DNS service. Without it every clusterset name is NXDOMAIN, and   #
# the symptom surfaces much later as brokers hanging on an unresolvable peer. #
#                                                                             #
# Reported rather than enforced: how the resolver is configured is a Submariner
# implementation detail that varies by distribution, and this procedure has    #
# already asserted one such detail that does not exist in this deployment mode.#
# The real gate is ../verify-cross-region-connectivity.sh, which resolves a    #
# clusterset name and then connects to it.                                    #
###############################################################################

echo
for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"

    if kubectl --context "$context" -n kube-system get configmap coredns -o yaml 2>/dev/null |
        grep -q "clusterset.local"; then
        echo "Clusterset DNS is wired into CoreDNS on $context"
    else
        echo "WARNING: no clusterset.local zone in the CoreDNS config of $context." >&2
        echo "         Cross-region names will not resolve unless Submariner wires the" >&2
        echo "         resolver another way. ../verify-cross-region-connectivity.sh will" >&2
        echo "         say for certain." >&2
    fi
done

echo
echo "Submariner service discovery is deployed across $CAMUNDA_ACTIVE_REGIONS clusters."
echo "It does not carry traffic: cross-region reachability comes from the Transit"
echo "Gateway and is proven by ../verify-cross-region-connectivity.sh."

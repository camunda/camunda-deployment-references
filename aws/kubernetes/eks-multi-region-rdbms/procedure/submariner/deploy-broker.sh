#!/bin/bash
set -euo pipefail

# Deploys the Submariner broker into one of the clusters.
#
# The broker is a metadata-only component: it holds the Endpoint and Cluster
# custom resources that let the gateways discover each other, plus the
# ServiceImport registry used by Lighthouse. Established IPsec tunnels keep
# working while it is unavailable, so it is deliberately not replicated across
# regions.
#
# It writes broker-info.subm into the current directory. That file contains the
# broker API endpoint and its credentials: treat it as a secret and delete it
# once every cluster has joined.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_BROKER_SLOT:?SUBMARINER_BROKER_SLOT must be set, source export_environment_prerequisites.sh}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
broker_context="${contexts[$SUBMARINER_BROKER_SLOT]}"

echo "Deploying the Submariner broker into $broker_context"

# Globalnet stays disabled: the reference architecture allocates
# non-overlapping VPC, pod and service CIDRs per region, which is a hard
# requirement of Transit Gateway routing anyway. Enabling Globalnet would add a
# NAT layer and a second address plan for no benefit here.
subctl deploy-broker \
    --context "$broker_context" \
    --globalnet=false

echo
echo "Broker deployed. broker-info.subm written to $(pwd)."
echo "It carries broker credentials: delete it once every cluster has joined."

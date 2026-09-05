#!/bin/bash
set -euo pipefail

# Deploys the Submariner broker into one of the clusters.
#
# Only the SERVICE DISCOVERY component is installed. Submariner is used here as
# a multi-cluster DNS layer, not as a data plane: with the AWS VPC CNI a pod
# address is an ordinary VPC address, so the Transit Gateway already carries
# cross-region pod traffic natively. Installing the connectivity component on
# top would put a second owner on the same prefixes -- Submariner routes them
# into an IPsec tunnel while AWS routes them natively -- which is a failure mode
# this architecture has already paid for. See ../../README.md, section
# "Cross-region networking".
#
# Consequences worth knowing:
#   * no gateway nodes, no IPsec, no VXLAN, no MTU overhead, nothing to fail
#     over: `subctl show connections` is empty by design;
#   * cross-region traffic crosses the AWS backbone unencrypted. It stays on
#     private addresses and never touches the internet, but if you need
#     confidentiality in transit, terminate TLS in the workload.
#
# The broker is a metadata-only component: it holds the ServiceImport registry
# Lighthouse resolves from. Its loss stops new exports from propagating but does
# not affect already published records, so it is deliberately not replicated.
#
# It writes broker-info.subm into the current directory. That file contains the
# broker API endpoint and its credentials: treat it as a secret and delete it
# once every cluster has joined.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_BROKER_SLOT:?SUBMARINER_BROKER_SLOT must be set, source export_environment_prerequisites.sh}"

# The component set is recorded in broker-info.subm and inherited by every
# cluster that joins, so it is fixed here rather than per cluster.
SUBMARINER_COMPONENTS="${SUBMARINER_COMPONENTS:-service-discovery}"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
broker_context="${contexts[$SUBMARINER_BROKER_SLOT]}"

echo "Deploying the Submariner broker into $broker_context"
echo "  components: $SUBMARINER_COMPONENTS"

# Globalnet stays disabled: the reference architecture allocates
# non-overlapping VPC and service CIDRs per region, which is a hard requirement
# of Transit Gateway routing anyway. Enabling Globalnet would add a NAT layer
# and a second address plan for no benefit here.
subctl deploy-broker \
    --context "$broker_context" \
    --components "$SUBMARINER_COMPONENTS" \
    --globalnet=false

echo
echo "Broker deployed. broker-info.subm written to $(pwd)."
echo "It carries broker credentials: delete it once every cluster has joined."

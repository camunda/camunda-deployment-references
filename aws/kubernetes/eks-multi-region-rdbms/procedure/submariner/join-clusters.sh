#!/bin/bash
set -euo pipefail

# Joins every active cluster to the Submariner broker.
#
# Run from the directory containing broker-info.subm (see deploy-broker.sh).
#
# Optional first argument: a single region slot to join, used by
# ../activate-region.sh when a new region is added to a running cluster.
#
# EKS specifics:
#   * --clustercidr is the POD CIDR, never the VPC CIDR. The pods live in the
#     VPC secondary CIDR set up by ../configure-vpc-cni-custom-networking.sh,
#     which the Transit Gateway deliberately does not route. Passing the VPC
#     CIDR here makes Submariner claim the whole routed range, AWS keeps
#     routing it natively, and cross-region pod traffic is silently dropped.
#     subctl cannot infer either value, hence the explicit flags.
#   * --air-gapped disables public IP discovery: gateways reach each other over
#     the private Transit Gateway mesh, never over the internet.
#   * --natt=false because there is no NAT between the peered VPCs.
#   * libreswan encrypts the tunnels. Transit Gateway traffic crosses the AWS
#     backbone unencrypted, so this is defence in depth rather than optional.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${REGION_POD_CIDRS:?REGION_POD_CIDRS must be set, e.g. from 'terraform output -json pod_cidr_blocks'}"
: "${REGION_SERVICE_CIDRS:?REGION_SERVICE_CIDRS must be set, e.g. from 'terraform output -json service_cidr_blocks'}"

BROKER_INFO="${BROKER_INFO:-broker-info.subm}"
CABLE_DRIVER="${SUBMARINER_CABLE_DRIVER:-libreswan}"

if [ ! -f "$BROKER_INFO" ]; then
    echo "ERROR: $BROKER_INFO not found. Run deploy-broker.sh first, or set BROKER_INFO." >&2
    exit 1
fi

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
read -r -a cluster_ids <<<"$SUBMARINER_CLUSTER_IDS"
read -r -a pod_cidrs <<<"$REGION_POD_CIDRS"
read -r -a service_cidrs <<<"$REGION_SERVICE_CIDRS"

join_slot() {
    local slot="$1"

    echo "Joining ${contexts[$slot]} as cluster id '${cluster_ids[$slot]}'"
    echo "  pod CIDR     : ${pod_cidrs[$slot]}"
    echo "  service CIDR : ${service_cidrs[$slot]}"
    subctl join "$BROKER_INFO" \
        --context "${contexts[$slot]}" \
        --clusterid "${cluster_ids[$slot]}" \
        --clustercidr "${pod_cidrs[$slot]}" \
        --servicecidr "${service_cidrs[$slot]}" \
        --cable-driver "$CABLE_DRIVER" \
        --natt=false \
        --air-gapped \
        --globalnet=false \
        --label-gateway=false \
        --check-broker-certificate=false
}

if [ $# -ge 1 ]; then
    join_slot "$1"
else
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        join_slot "$i"
    done
fi

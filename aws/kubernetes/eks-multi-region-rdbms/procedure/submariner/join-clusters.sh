#!/bin/bash
set -euo pipefail

# Joins every active cluster to the Submariner broker.
#
# Run from the directory containing broker-info.subm (see deploy-broker.sh).
#
# Optional first argument: a single region slot to join, used by
# ../activate-region.sh when a new region is added to a running cluster.
#
# The broker carries only the service-discovery component, so joining installs
# Lighthouse and nothing else: no gateway, no IPsec, no route agent. Every flag
# below is therefore about ADDRESSING, not about a data plane:
#
#   * --clustercidr is the pod range, which with the AWS VPC CNI is the VPC
#     range: pod addresses are ordinary VPC addresses. subctl cannot infer it
#     reliably on EKS, hence the explicit value.
#   * --servicecidr is what Lighthouse resolves a remote ClusterIP service to.
#
# Both are carried to the broker so the other clusters know which prefixes
# belong to which cluster. Reaching them is the Transit Gateway's job.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${REGION_VPC_CIDRS:?REGION_VPC_CIDRS must be set, e.g. from 'terraform output -json vpc_cidr_blocks'}"
: "${REGION_SERVICE_CIDRS:?REGION_SERVICE_CIDRS must be set, e.g. from 'terraform output -json service_cidr_blocks'}"

BROKER_INFO="${BROKER_INFO:-broker-info.subm}"

if [ ! -f "$BROKER_INFO" ]; then
    echo "ERROR: $BROKER_INFO not found. Run deploy-broker.sh first, or set BROKER_INFO." >&2
    exit 1
fi

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
read -r -a cluster_ids <<<"$SUBMARINER_CLUSTER_IDS"
read -r -a vpc_cidrs <<<"$REGION_VPC_CIDRS"
read -r -a service_cidrs <<<"$REGION_SERVICE_CIDRS"

join_slot() {
    local slot="$1"

    echo "Joining ${contexts[$slot]} as cluster id '${cluster_ids[$slot]}'"
    echo "  pod (VPC) CIDR : ${vpc_cidrs[$slot]}"
    echo "  service CIDR   : ${service_cidrs[$slot]}"

    # --label-gateway=false because there is no gateway to schedule: the
    # connectivity component is not installed.
    #
    # The broker certificate is verified. Turning that off is what makes joining
    # the wrong endpoint, or one in the middle, succeed quietly, and the join is
    # how a cluster learns where to send its service discovery. Left as an escape
    # hatch for a broker behind a certificate the joining cluster cannot chain to,
    # which is a thing to fix rather than to carry.
    subctl join "$BROKER_INFO" \
        --context "${contexts[$slot]}" \
        --clusterid "${cluster_ids[$slot]}" \
        --clustercidr "${vpc_cidrs[$slot]}" \
        --servicecidr "${service_cidrs[$slot]}" \
        --globalnet=false \
        --label-gateway=false \
        --check-broker-certificate="${SUBMARINER_CHECK_BROKER_CERTIFICATE:-true}"
}

if [ $# -ge 1 ]; then
    join_slot "$1"
else
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        join_slot "$i"
    done
fi

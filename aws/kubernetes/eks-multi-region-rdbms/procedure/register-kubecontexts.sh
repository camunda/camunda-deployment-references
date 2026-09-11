#!/bin/bash
set -euo pipefail

# Registers a kubectl context per deployed region, aliased `cluster-<short name>`
# so that CLUSTER_CONTEXTS addresses them:
#
#   . ./export-terraform-outputs.sh
#   ./register-kubecontexts.sh
#
# Idempotent: `aws eks update-kubeconfig` overwrites an alias it already wrote,
# so this can run again after a region is added.

: "${AWS_REGIONS:?AWS_REGIONS must be set, source export-terraform-outputs.sh}"
: "${EKS_CLUSTER_NAMES:?EKS_CLUSTER_NAMES must be set, source export-terraform-outputs.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export-terraform-outputs.sh}"

read -r -a _regions <<<"$AWS_REGIONS"
read -r -a _names <<<"$EKS_CLUSTER_NAMES"
read -r -a _shorts <<<"$SUBMARINER_CLUSTER_IDS"

for i in "${!_shorts[@]}"; do
    aws eks --region "${_regions[$i]}" update-kubeconfig \
        --name "${_names[$i]}" \
        --alias "cluster-${_shorts[$i]}"
done

kubectl config get-contexts

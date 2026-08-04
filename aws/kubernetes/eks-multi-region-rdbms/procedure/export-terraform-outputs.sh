#!/bin/bash
set -euo pipefail

# Exports the Terraform outputs of terraform/clusters into the shell variables
# consumed by the other procedures:
#
#   . ./export-terraform-outputs.sh
#
# A single `terraform output -json` call is used on purpose: repeated
# `terraform output -raw` invocations each take the state lock, which is slow
# and contends with a concurrent apply.

: "${TF_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform/clusters" && pwd)}"

_tf_json="$(terraform -chdir="$TF_DIR" output -json)"

_tf_get() { echo "$_tf_json" | jq -r "$1"; }

export CAMUNDA_REGION_SLOTS="$(_tf_get '.region_slot_count.value')"
export CAMUNDA_ACTIVE_REGIONS="$(_tf_get '.active_region_count.value')"

# Region-indexed maps are flattened into space-separated lists in slot order.
export AWS_REGIONS="$(_tf_get '[.regions.value | to_entries | sort_by(.key | tonumber) | .[].value.region] | join(" ")')"
export SUBMARINER_CLUSTER_IDS="$(_tf_get '[.regions.value | to_entries | sort_by(.key | tonumber) | .[].value.short_name] | join(" ")')"
export REGION_VPC_CIDRS="$(_tf_get '[.vpc_cidr_blocks.value | to_entries | sort_by(.key | tonumber) | .[].value] | join(" ")')"
export REGION_SERVICE_CIDRS="$(_tf_get '[.service_cidr_blocks.value | to_entries | sort_by(.key | tonumber) | .[].value] | join(" ")')"
# Pods live in a VPC secondary CIDR that the Transit Gateway does not route.
# This, not REGION_VPC_CIDRS, is what Submariner must be joined with.
export REGION_POD_CIDRS="$(_tf_get '[.pod_cidr_blocks.value | to_entries | sort_by(.key | tonumber) | .[].value] | join(" ")')"
export EKS_CLUSTER_NAMES="$(_tf_get '[.cluster_names.value | to_entries | sort_by(.key | tonumber) | .[].value] | join(" ")')"

export CAMUNDA_RDBMS_URL="$(_tf_get '.camunda_rdbms_url.value // empty')"
export CAMUNDA_RDBMS_USERNAME="$(_tf_get '.database_username.value // empty')"
export CAMUNDA_RDBMS_PASSWORD="$(_tf_get '.database_password.value // empty')"
export AURORA_GLOBAL_CLUSTER_ID="$(_tf_get '.database_global_cluster_id.value // empty')"

unset _tf_json

echo "Terraform outputs exported:"
echo "  region slots   : $CAMUNDA_REGION_SLOTS (active: $CAMUNDA_ACTIVE_REGIONS)"
echo "  aws regions    : $AWS_REGIONS"
echo "  eks clusters   : $EKS_CLUSTER_NAMES"
echo "  submariner ids : $SUBMARINER_CLUSTER_IDS"
echo "  node CIDRs     : $REGION_VPC_CIDRS"
echo "  pod CIDRs      : $REGION_POD_CIDRS"
echo "  rdbms url      : ${CAMUNDA_RDBMS_URL:-<unset>}"

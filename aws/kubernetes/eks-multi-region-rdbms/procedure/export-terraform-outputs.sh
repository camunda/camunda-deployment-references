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

# How many slots Terraform has provisioned, which is not how many regions run
# Camunda. Activating a slot builds its infrastructure first and deploys into it
# afterwards, so the two disagree for the length of that procedure, and the
# activation reads the Camunda-side count to know which slot to bring up. A
# caller that already knows it therefore keeps it.
export TF_ACTIVE_REGION_COUNT="$(_tf_get '.active_region_count.value')"
export CAMUNDA_ACTIVE_REGIONS="${CAMUNDA_ACTIVE_REGIONS:-$TF_ACTIVE_REGION_COUNT}"

# Region-indexed maps are flattened into space-separated lists in slot order.
export AWS_REGIONS="$(_tf_get '[.regions.value | to_entries | sort_by(.key | tonumber) | .[].value.region] | join(" ")')"
export SUBMARINER_CLUSTER_IDS="$(_tf_get '[.regions.value | to_entries | sort_by(.key | tonumber) | .[].value.short_name] | join(" ")')"
# The kubectl context of a cluster is its Submariner ID prefixed with `cluster-`;
# register-kubecontexts.sh creates them under exactly those aliases.
export CLUSTER_CONTEXTS="$(_tf_get '[.regions.value | to_entries | sort_by(.key | tonumber) | .[].value.short_name | "cluster-" + .] | join(" ")')"
export REGION_VPC_CIDRS="$(_tf_get '[.vpc_cidr_blocks.value | to_entries | sort_by(.key | tonumber) | .[].value] | join(" ")')"
export REGION_SERVICE_CIDRS="$(_tf_get '[.service_cidr_blocks.value | to_entries | sort_by(.key | tonumber) | .[].value] | join(" ")')"
# Every zone, not only the active ones: the Camunda zone list covers the whole
# topology. SUBMARINER_CLUSTER_IDS is the active subset and is not a substitute.
export CAMUNDA_ZONE_NAMES="$(_tf_get '.zone_names.value | join(" ")')"
export EKS_CLUSTER_NAMES="$(_tf_get '[.cluster_names.value | to_entries | sort_by(.key | tonumber) | .[].value] | join(" ")')"

export CAMUNDA_RDBMS_URL="$(_tf_get '.camunda_rdbms_url.value // empty')"
export CAMUNDA_RDBMS_USERNAME="$(_tf_get '.database_username.value // empty')"
export CAMUNDA_RDBMS_PASSWORD="$(_tf_get '.database_password.value // empty')"
export AURORA_GLOBAL_CLUSTER_ID="$(_tf_get '.database_global_cluster_id.value // empty')"

unset _tf_json

echo "Terraform outputs exported:"
echo "  region slots   : $CAMUNDA_REGION_SLOTS (provisioned: $TF_ACTIVE_REGION_COUNT, running Camunda: $CAMUNDA_ACTIVE_REGIONS)"
echo "  aws regions    : $AWS_REGIONS"
echo "  contexts       : $CLUSTER_CONTEXTS"
echo "  eks clusters   : $EKS_CLUSTER_NAMES"
echo "  submariner ids : $SUBMARINER_CLUSTER_IDS"
echo "  zone names     : $CAMUNDA_ZONE_NAMES"
echo "  vpc CIDRs      : $REGION_VPC_CIDRS"
echo "  rdbms url      : ${CAMUNDA_RDBMS_URL:-<unset>}"

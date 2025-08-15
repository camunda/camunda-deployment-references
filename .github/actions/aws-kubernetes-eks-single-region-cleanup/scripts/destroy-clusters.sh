#!/bin/bash
set -o pipefail

# Description:
# This script performs Terraform destroy operations for infrastructures stored in an S3 bucket.
# Each "group_id" directory may contain up to two separate modules, each with its own state file:
#   1. vpn.tfstate
#   2. cluster.tfstate
#
# The script ensures proper ordering: if both VPN and cluster exist, the VPN module is destroyed first,
# followed by the cluster module. It copies a dummy config.tf, initializes Terraform with the appropriate
# backend configuration, and runs `terraform destroy`. Upon successful destruction, it cleans up the
# corresponding S3 objects.
#
# Additionally, if the environment variable `RETRY_DESTROY` is set, the script invokes `cloud-nuke`
# to remove any remaining VPC resources that Terraform may not have deleted.
#
# Usage:
# ./destroy_clusters.sh <BUCKET> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX] [--fail-on-not-found]
#
# Arguments:
#   BUCKET: The name of the S3 bucket containing the Terraform state files.
#   MIN_AGE_IN_HOURS: Minimum age (in hours) of clusters to be destroyed.
#   ID_OR_ALL: Specific group_id to filter objects, or "all" to destroy everything.
#   KEY_PREFIX (optional): Prefix (with trailing '/') for filtering objects in the S3 bucket.
#   --fail-on-not-found (optional): If set, the script exits with an error when no matching object is found
#                                  (only used when ID_OR_ALL is not "all").
#
# Requirements:
# - AWS CLI installed and configured with permissions to access and modify the S3 bucket.
# - Terraform installed and accessible in the PATH.
# - `yq` installed when using `RETRY_DESTROY`.

# Variables
BUCKET=$1
MIN_AGE_IN_HOURS=$2
ID_OR_ALL=$3
KEY_PREFIX=""
FAILED=0
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
AWS_S3_REGION=${AWS_S3_REGION:-$AWS_REGION}
FAIL_ON_NOT_FOUND=false

# Handle optional KEY_PREFIX and flag
for arg in "${@:4}"; do
  if [ "$arg" == "--fail-on-not-found" ]; then
    FAIL_ON_NOT_FOUND=true
  else
    KEY_PREFIX="$arg"
  fi
done

# Date command
if [[ "$(uname)" == "Darwin" ]]; then
    date_command="gdate"
else
    date_command="date"
fi

destroy_module() {
  local group_id=$1
  local module_name=$2
  local key="$KEY_PREFIX""tfstate-$group_id/${module_name}.tfstate"
  local temp_dir="/tmp/${group_id}_${module_name}"

  mkdir -p "$temp_dir"
  cp "$SCRIPT_DIR/config.tf" "$temp_dir/"
  cd "$temp_dir" || return 1

  echo "[$group_id][$module_name] Initializing Terraform with state $key"
  terraform init -backend-config="bucket=$BUCKET" -backend-config="key=$key" -backend-config="region=$AWS_S3_REGION" || return 1

  # Remove storage class if blocking destroy
  terraform state rm 'module.eks_cluster.kubernetes_storage_class_v1.ebs_sc[0]' >/dev/null 2>&1 || true

  echo "[$group_id][$module_name] Destroying module"
  terraform destroy -auto-approve || return 1

  # Cleanup S3
  echo "[$group_id][$module_name] Cleaning up S3"
  aws s3 rm "s3://$BUCKET/tfstate-$group_id/${module_name}.tfstate" || true

  cd - >/dev/null || return 1
  rm -rf "$temp_dir"
}

# Fetch all group IDs
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive)
aws_exit_code=$?

# don't fail on folder absent
if [ $aws_exit_code -ne 0 ] && [ "$all_objects" != "" ]; then
  echo "Error executing the aws s3 ls command (Exit Code: $aws_exit_code):" >&2
  exit 1
fi

if [ "$ID_OR_ALL" == "all" ]; then
  groups=$(echo "$all_objects" | awk '{print $NF}' | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p' | sort -u)
else
  groups=$(echo "$all_objects" | awk '{print $NF}' | grep "tfstate-$ID_OR_ALL/" | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p' | sort -u)
  if [ -z "$groups" ] && [ "$FAIL_ON_NOT_FOUND" = true ]; then
    echo "Error: No object found for ID '$ID_OR_ALL'"
    exit 1
  fi
fi

current_timestamp=$($date_command +%s)
log_dir="./logs"
mkdir -p "$log_dir"

pids=()

for group_id in $groups; do
  log_file="$log_dir/$group_id.log"
  (
    echo "[$group_id] Processing group"

    # Order: vpn → cluster
    for module in vpn cluster; do
      key="$KEY_PREFIX""tfstate-$group_id/${module}.tfstate"
      if aws s3 ls "s3://$BUCKET/$key" >/dev/null 2>&1; then
        last_modified=$(aws s3api head-object --bucket "$BUCKET" --key "$key" --query 'LastModified' --output text)
        last_modified_ts=$($date_command -d "$last_modified" +%s)
        age_hours=$(( (current_timestamp - last_modified_ts) / 3600 ))
        echo "[$group_id][$module] Last modified: $last_modified ($age_hours hours old)"
        if [ "$age_hours" -ge "$MIN_AGE_IN_HOURS" ]; then
          destroy_module "$group_id" "$module" || exit 1
        else
          echo "[$group_id][$module] Skipping (age < $MIN_AGE_IN_HOURS hours)"
        fi
      else
        echo "[$group_id][$module] Not found, skipping..."
      fi
    done
  ) >"$log_file" 2>&1 &
  pids+=($!)
done

# Live logs
tail -n 0 -f "$log_dir"/*.log &
tail_pid=$!

FAILED=0
for pid in "${pids[@]}"; do
  wait "$pid" || FAILED=1
done

kill "$tail_pid" 2>/dev/null

if [ $FAILED -ne 0 ]; then
  echo "One or more operations failed."
  exit 1
fi

echo "All operations completed successfully."
exit 0

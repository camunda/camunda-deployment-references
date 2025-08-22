#!/bin/bash
set -o pipefail

# Description:
# This script destroys Terraform-managed infrastructures stored in an S3 bucket.
# Each "group_id" may contain two modules:
#   - vpn.tfstate
#   - cluster.tfstate
#
# The destruction order (e.g., "vpn,cluster" or "cluster,vpn") must be passed
# as a required script parameter.

# Usage:
# ./destroy-resources.sh <BUCKET> <MIN_AGE_IN_HOURS> <ID_OR_ALL> <ORDER> [KEY_PREFIX] [--fail-on-not-found]
#
# Arguments:
#   BUCKET: Name of the S3 bucket containing the Terraform state files.
#   MIN_AGE_IN_HOURS: Minimum age (in hours) of clusters to be destroyed.
#   ID_OR_ALL: Specific group_id to target, or "all".
#   ORDER: Destruction order, e.g. "vpn,cluster" or "cluster,vpn".
#   KEY_PREFIX (optional): Prefix for S3 keys.
#   --fail-on-not-found (optional): Fail if no object is found when ID_OR_ALL != "all".
#
# Supports dry-run mode via DRY_RUN=true.

# Variables
BUCKET=$1
MIN_AGE_IN_HOURS=$2
ID_OR_ALL=$3
ORDER=$4
KEY_PREFIX=""
FAILED=0
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
AWS_S3_REGION=${AWS_S3_REGION:-$AWS_REGION}
FAIL_ON_NOT_FOUND=false
DRY_RUN=${DRY_RUN:-false}

# Validate ORDER argument
if [[ -z "$ORDER" ]]; then
  echo "Error: destruction ORDER must be provided (e.g. 'vpn,cluster' or 'cluster,vpn')."
  exit 1
fi

IFS=',' read -r -a ORDERED_MODULES <<< "$ORDER"

# Handle optional args (KEY_PREFIX and flag)
for arg in "${@:5}"; do
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

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN][$group_id][$module_name] Would initialize Terraform with state $key"
    echo "[DRY RUN][$group_id][$module_name] Would destroy module '$module_name'"
    echo "[DRY RUN][$group_id][$module_name] Would remove s3://$BUCKET/$key"
    return 0
  fi

  if [[  "$module_name" == "cluster" && "$RETRY_DESTROY" == "true" ]]; then
    echo "Performing cloud-nuke on VPC to ensure that resources managed outside of Terraform are deleted."
    yq eval ".VPC.include.names_regex = [\"^$group_id.*\"]" -i "$SCRIPT_DIR/matching-vpc.yml"
    cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$AWS_REGION" --force
  fi

  mkdir -p "$temp_dir"
  cp "$SCRIPT_DIR/config" "$temp_dir/config.tf" || return 1
  cd "$temp_dir" || return 1

  echo "[$group_id][$module_name] Initializing Terraform with state $key"
  terraform init -backend-config="bucket=$BUCKET" -backend-config="key=$key" -backend-config="region=$AWS_S3_REGION" || return 1

  if [[ "$module_name" == "vpn" ]]; then
    deducted_vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${group_id}*" --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION")

    if [[ "$deducted_vpc_id" == "None" || -z "$deducted_vpc_id" ]]; then
      echo "Error: VPC = $deducted_vpc_id not found."

      echo "Assuming it was deleted by Cloud Nuke. Cleaning up Terraform state..."
      aws s3 rm "s3://$BUCKET/$key" || true
      cd - >/dev/null || return 1
      rm -rf "$temp_dir"

      return 0
    fi
  fi

  echo "[$group_id][$module_name] Destroying module"
  if ! output_tf_destroy=$(terraform destroy -auto-approve 2>&1); then
    echo "$output_tf_destroy"

    if [[ "$module_name" == "cluster" && "$output_tf_destroy" == *"CLUSTERS-MGMT-404"* ]]; then
      echo "The cluster appears to have already been deleted (error: CLUSTERS-MGMT-404). Considering the deletion successful (likely due to cloud-nuke)."
    else
      echo "Error destroying module $module_name in group $group_id"
      return 1
    fi
  fi

  echo "[$group_id][$module_name] Cleaning up S3"
  aws s3 rm "s3://$BUCKET/$key" || true

  cd - >/dev/null || return 1
  rm -rf "$temp_dir"
}

# Fetch all group IDs
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive)
aws_exit_code=$?

# Don't fail on missing folder
if [ $aws_exit_code -ne 0 ] && [ "$all_objects" != "" ]; then
  echo "Error executing aws s3 ls (Exit Code: $aws_exit_code)." >&2
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

    # Use the ORDER parameter for modules cleanup
    for module in "${ORDERED_MODULES[@]}"; do
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

if [ "$DRY_RUN" == "true" ]; then
  echo "Dry run completed. No changes were made."
  exit 0
fi

if [ $FAILED -ne 0 ]; then
  echo "One or more operations failed."
  exit 1
fi

echo "All operations completed successfully."
exit 0

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
  local key="${KEY_PREFIX}tfstate-$group_id/${module_name}.tfstate"
  local temp_dir="/tmp/${group_id}_${module_name}"

  cleanup_state() {
    echo "[$group_id][$module_name] Cleaning up Terraform state: s3://$BUCKET/$key"
    aws s3 rm "s3://$BUCKET/$key" || true
    cd - >/dev/null || return 1
    rm -rf "$temp_dir"
  }

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN][$group_id][$module_name] Would init Terraform with $key, destroy, and remove s3://$BUCKET/$key"
    return 0
  fi

  # Special handling for single-cluster destroy with retries
  if [[ "$module_name" == "cluster" && "$RETRY_DESTROY" == "true" ]]; then
    echo "Retry destroy: nuking VPC for $group_id..."
    yq eval ".VPC.include.names_regex = [\"^$group_id.*\"]" -i "$SCRIPT_DIR/matching-vpc.yml"
    cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$AWS_REGION" --force
  fi

  # Handle dual-region (we may need a better way to abstract this)
  local tf_config_file="$SCRIPT_DIR/config"
  if [[ "$module_name" =~ ^(clusters|peering)$ ]]; then
    [[ -z "$CLUSTER_1_AWS_REGION" || -z "$CLUSTER_2_AWS_REGION" ]] && {
      echo "Error: CLUSTER_1_AWS_REGION and CLUSTER_2_AWS_REGION must be set"
      exit 1
    }

    local cluster_1_name cluster_2_name
    cluster_1_name=$(echo "$group_id" | awk -F"-oOo-" '{print $1}')
    cluster_2_name=$(echo "$group_id" | awk -F"-oOo-" '{print $2}')

    tf_config_file="$SCRIPT_DIR/config-dual-region"

    if [[ "$RETRY_DESTROY" == "true" ]]; then
      echo "Retry destroy: nuking dual-region VPCs..."
      yq eval ".VPC.include.names_regex = [\"^$cluster_1_name.*\", \"^$cluster_2_name.*\"]" -i "$SCRIPT_DIR/matching-vpc.yml"
      cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$CLUSTER_1_AWS_REGION" --force
      cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$CLUSTER_2_AWS_REGION" --force
    fi

    # Peering module check: we verify if both VPCs exist because the peering module contains data blocks
    # that will fail if either VPC is not found. In this case, we directly clean up the state.
    if [[ "$module_name" == "peering" ]]; then
      local vpc1 vpc2
      vpc1=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_1_name}*" \
             --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION")
      vpc2=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_2_name}*" \
             --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_2_AWS_REGION")

      if [[ "$vpc1" == "None" || -z "$vpc1" || "$vpc2" == "None" || -z "$vpc2" ]]; then
        echo "Error: Missing VPCs ($vpc1 / $vpc2), assuming nuked."
        cleanup_state
        return 0
      fi
    fi
  fi

  mkdir -p "$temp_dir"
  cp "$tf_config_file" "$temp_dir/config.tf" || return 1
  cd "$temp_dir" || return 1

  echo "[$group_id][$module_name] Initializing Terraform"
  if [[ "$tf_config_file" == *"config-dual-region" ]]; then
    terraform init \
      -backend-config="bucket=$BUCKET" \
      -backend-config="key=$key" \
      -backend-config="region=$AWS_S3_REGION" \
      -var="cluster_1_region=$CLUSTER_1_AWS_REGION" \
      -var="cluster_2_region=$CLUSTER_2_AWS_REGION" || return 1
  else
    terraform init \
      -backend-config="bucket=$BUCKET" \
      -backend-config="key=$key" \
      -backend-config="region=$AWS_S3_REGION" || return 1
  fi

  if [[ "$module_name" == "backup_bucket" ]]; then
    echo "[$group_id][$module_name] Emptying S3 backup buckets before destroy"
    BACKUP_BUCKET_S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)

    for TMP_BUCKET in "$BACKUP_BUCKET_S3_BUCKET_NAME" "${BACKUP_BUCKET_S3_BUCKET_NAME}-log"; do
      if ! aws s3api head-bucket --bucket "$TMP_BUCKET" --no-cli-pager 2>/dev/null; then
        echo "ℹ️  Bucket $TMP_BUCKET does not exist, skipping."
        continue
      fi

      echo "🧹 Emptying bucket: $TMP_BUCKET"
      aws s3 rm "s3://${TMP_BUCKET}" --recursive || true

      MAX_ITERATIONS=100
      ITERATION=0
      while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
        JSON=$(aws s3api list-object-versions --bucket "$TMP_BUCKET" --output=json || echo '{}')
        VERSIONS=$(echo "$JSON" | jq -c '[.Versions[]? | {Key, VersionId}]')
        MARKERS=$(echo "$JSON" | jq -c '[.DeleteMarkers[]? | {Key, VersionId}]')

        VER_COUNT=$(echo "$VERSIONS" | jq 'length')
        MAR_COUNT=$(echo "$MARKERS" | jq 'length')

        if [[ "$VER_COUNT" -eq 0 && "$MAR_COUNT" -eq 0 ]]; then
          echo "✅ Bucket $TMP_BUCKET is now empty."
          break
        fi

        if [[ "$VER_COUNT" -gt 0 ]]; then
          echo "🗑️  Deleting $VER_COUNT object versions..."
          aws s3api delete-objects --bucket "$TMP_BUCKET" \
            --delete "{\"Objects\": $VERSIONS}" >/dev/null || true
        fi

        if [[ "$MAR_COUNT" -gt 0 ]]; then
          echo "🧹 Deleting $MAR_COUNT delete markers..."
          aws s3api delete-objects --bucket "$TMP_BUCKET" \
            --delete "{\"Objects\": $MARKERS}" >/dev/null || true
        fi

        ITERATION=$((ITERATION + 1))
      done

      [[ $ITERATION -ge $MAX_ITERATIONS ]] && echo "⚠️  Warning: Max iterations reached for $TMP_BUCKET"
    done
  fi

  # VPN module check: we verify if the VPC exists because the VPN module contains data blocks
  # that will fail if the VPC is not found. In this case, we directly clean up the state.
  if [[ "$module_name" == "vpn" ]]; then
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${group_id}*" \
             --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION")
    if [[ "$vpc_id" == "None" || -z "$vpc_id" ]]; then
      echo "Error: VPC not found ($vpc_id), assuming nuked."
      cleanup_state
      return 0
    fi
  fi

  echo "[$group_id][$module_name] Destroying module"
  if ! output=$(terraform destroy -auto-approve 2>&1); then
    echo "$output"
    if [[ "$module_name" =~ ^(cluster|clusters)$ && "$output" == *"CLUSTERS-MGMT-404"* ]]; then
      echo "Cluster already deleted (CLUSTERS-MGMT-404). Considering successful."
    else
      echo "Error destroying $module_name in $group_id"
      return 1
    fi
  fi

  echo "[$group_id][$module_name] Cleaning up"
  cleanup_state
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
  groups=$(echo "$all_objects" | awk '{print $NF}' | grep "$ID_OR_ALL" | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p' | sort -u)
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

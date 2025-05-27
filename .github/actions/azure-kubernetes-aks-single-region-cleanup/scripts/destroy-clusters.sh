#!/bin/bash

set -o pipefail

# Description:
# This script performs a Terraform destroy operation for resources defined in an S3 bucket.
# It copies a dummy config.tf, initializes Terraform with
# the appropriate backend configuration, and runs `terraform destroy`. If the destroy operation
# is successful, it removes the corresponding S3 objects.
#
# The target region is defined using `AZURE_REGION`.
#
# Additionally, if the environment variable `RETRY_DESTROY` is set, the script will invoke Azure
# Resource Group deletion to clean up any unmanaged Azure resources.
#
# Usage:
# ./destroy-clusters.sh <BUCKET> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX]
#
# Arguments:
#   BUCKET: The name of the S3 bucket containing the cluster state files.
#   MIN_AGE_IN_HOURS: The minimum age (in hours) of clusters to be destroyed.
#   ID_OR_ALL: The specific ID suffix to filter objects, or "all" to destroy all objects (likely the resources group).
#   KEY_PREFIX (optional): A prefix (with a '/' at the end) for filtering objects in the S3 bucket.
#
# Example:
# ./destroy-clusters.sh tf-state-ci-eu-west-3 24 all
# ./destroy-clusters.sh tf-state-ci-eu-west-3 24 aks-cluster-2883
# ./destroy-clusters.sh tf-state-ci-eu-west-3 24 all my-prefix/
#
# Requirements:
# - AWS CLI installed and configured with the necessary permissions to access and modify the S3 bucket.
# - Terraform installed and accessible in the PATH.
# - Azure CLI installed and logged in when you use `RETRY_DESTROY`.

# Check for required arguments
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <BUCKET> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX]"
  exit 1
fi

if [ -z "$AZURE_REGION" ]; then
  echo "Error: The environment variable AZURE_REGION is not set."
  exit 1
fi

if [ -z "$AWS_S3_REGION" ]; then
  echo "Error: The environment variable AWS_S3_REGION is not set."
  exit 1
fi

# Variables
BUCKET=$1
MIN_AGE_IN_HOURS=$2
ID_OR_ALL=$3
KEY_PREFIX=${4:-""}
FAILED=0
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Detect operating system and set the appropriate date command
if [[ "$(uname)" == "Darwin" ]]; then
  date_command="gdate"
else
  date_command="date"
fi

# Function to perform terraform destroy
destroy_group() {
  local key=$1
  local group_id
  local group_folder

  # shellcheck disable=SC2001 # the alternative is multiple bash expansions
  group_id=$(echo "$key" | sed 's|.*/tfstate-\([^/]*\)/.*|\1|')
  # shellcheck disable=SC2001 # the alternative is multiple bash expansions
  group_folder=$(echo "$key" | sed 's|\(.*\)/.*|\1|')

  mkdir -p "/tmp/$group_id"
  cp "$SCRIPT_DIR/config" "/tmp/$group_id/config.tf"
  cd "/tmp/$group_id" || exit 1

  # ─── In case of a failure, we delete the whole resource group ───
  if [[ "$RETRY_DESTROY" == "true" ]]; then
    # Get the region of the resource group
    rg_region=$(az group show --name "$group_id" --query "location" -o tsv)

    if [[ "$rg_region" == "$AZURE_REGION" ]]; then
      echo "Enforcing deletion of Resource Group: $group_id in region $rg_region"

      az lock list --resource-group "$group_id" --query "[].id" -o tsv | while IFS= read -r LOCK_ID; do
        az lock delete --ids "$LOCK_ID" 2>/dev/null || echo "Failed to delete lock: $LOCK_ID"
      done

      az group delete --name "$group_id" --yes
    else
      echo "Skipping $group_id – region mismatch (expected: $AZURE_REGION, actual: $rg_region)"
    fi
  fi

  echo "tf state: bucket=$BUCKET key=$key region=$AWS_S3_REGION"

  if ! terraform init \
      -backend-config="bucket=$BUCKET" \
      -backend-config="key=$key" \
      -backend-config="region=$AWS_S3_REGION"; then
    return 1
  fi

  if ! terraform destroy -auto-approve; then
    return 1
  fi

  # Cleanup S3
  echo "Deleting s3://$BUCKET/$group_folder"
  aws s3 rm "s3://$BUCKET/$group_folder" --recursive || return 1
  aws s3api delete-object --bucket "$BUCKET" --key "$group_folder/" || return 1

  cd - >/dev/null || exit 1
  rm -rf "/tmp/$group_id"
}

# Gather all state files from S3
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive)
aws_exit_code=$?

# don't fail on folder absent
if [ $aws_exit_code -ne 0 ] && [ "$all_objects" != "" ]; then
  echo "Error executing the aws s3 ls command (Exit Code: $aws_exit_code):" >&2
  exit 1
fi

# Filter groups IDs
if [ "$ID_OR_ALL" == "all" ]; then
  groups=$(echo "$all_objects" | awk '{print $NF}' \
    | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p')
else
  groups=$(echo "$all_objects" | awk '{print $NF}' \
    | grep "tfstate-$ID_OR_ALL/" \
    | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p')
fi

if [ -z "$groups" ]; then
  echo "No matching group found; nothing to do."
  exit 0
fi

current_timestamp=$($date_command +%s)

# Prepare logs directory
log_dir="./logs"
mkdir -p "$log_dir"

# Launch destroys in parallel
pids=()
for group_id in $groups; do
  log_file="$log_dir/$group_id.log"

  (
    group_folder="tfstate-$group_id"
    echo "[$group_id] Checking last modified for ${group_id}.tfstate..."

    last_modified=$(aws s3api head-object \
      --bucket "$BUCKET" \
      --key "$KEY_PREFIX$group_folder/${group_id}.tfstate" \
      --query 'LastModified' --output text)
    if [ -z "$last_modified" ]; then
      echo "[$group_id] ERROR: Could not fetch LastModified"
      exit 1
    fi

    last_ts=$($date_command -d "$last_modified" +%s)
    age_hours=$(( (current_timestamp - last_ts) / 3600 ))
    echo "[$group_id] Last modified: $last_modified ($age_hours hours ago)"

    if [ $age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
      echo "[$group_id] Destroying..."
      if ! destroy_group "$KEY_PREFIX$group_folder/${group_id}.tfstate"; then
        echo "[$group_id] ERROR during destroy"
        exit 1
      fi
      echo "[$group_id] Destroy succeeded"
    else
      echo "[$group_id] Skipping (only $age_hours hours old)"
    fi
  ) >"$log_file" 2>&1 &

  pids+=($!)
done

# Live-tail all logs
echo "=== Live logs ==="
tail -n 0 -f "$log_dir"/*.log &
tail_pid=$!

# Wait for all background jobs
for pid in "${pids[@]}"; do
  wait "$pid" || FAILED=1
done

# Stop tail
kill $tail_pid 2>/dev/null

if [ $FAILED -ne 0 ]; then
  echo "One or more destroy operations failed."
  exit 1
else
  echo "All destroys completed successfully."
  exit 0
fi

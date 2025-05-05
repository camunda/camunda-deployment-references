#!/bin/bash

set -o pipefail

# Description:
# This script performs a Terraform destroy operation for clusters defined in an S3 bucket.
# It copies a dummy config.tf, initializes Terraform with
# the appropriate backend configuration, and runs `terraform destroy`. If the destroy operation
# is successful, it removes the corresponding S3 objects.
#
# Additionally, if the environment variable `RETRY_DESTROY` is set, the script will invoke Azure
# Resource Group deletion to clean up any unmanaged Azure resources.
#
# Usage:
# ./destroy_clusters.sh <BUCKET> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX]
#
# Arguments:
#   BUCKET: The name of the S3 bucket containing the cluster state files.
#   MIN_AGE_IN_HOURS: The minimum age (in hours) of clusters to be destroyed.
#   ID_OR_ALL: The specific ID suffix to filter objects, or "all" to destroy all objects.
#   KEY_PREFIX (optional): A prefix (with a '/' at the end) for filtering objects in the S3 bucket.
#
# Example:
# ./destroy_clusters.sh tf-state-rosa-ci-eu-west-3 24 all
# ./destroy_clusters.sh tf-state-rosa-ci-eu-west-3 24 eks-cluster-2883
# ./destroy_clusters.sh tf-state-rosa-ci-eu-west-3 24 all my-prefix/
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

if [ -z "$AWS_REGION" ]; then
  echo "Error: The environment variable AWS_REGION is not set."
  exit 1
fi

# Variables
BUCKET=$1
MIN_AGE_IN_HOURS=$2
ID_OR_ALL=$3
KEY_PREFIX=${4:-""}
FAILED=0
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
AWS_S3_REGION=${AWS_S3_REGION:-$AWS_REGION}

# Detect operating system and set the appropriate date command
if [[ "$(uname)" == "Darwin" ]]; then
  date_command="gdate"
else
  date_command="date"
fi

# Function to perform terraform destroy
destroy_cluster() {
  local key=$1
  local cluster_id
  local cluster_folder

  # shellcheck disable=SC2001 # the alternative is multiple bash expansions
  cluster_id=$(echo "$key" | sed 's|.*/tfstate-\([^/]*\)/.*|\1|')
  # shellcheck disable=SC2001 # the alternative is multiple bash expansions
  cluster_folder=$(echo "$key" | sed 's|\(.*\)/.*|\1|')

  mkdir -p "/tmp/$cluster_id"
  cp "$SCRIPT_DIR/config" "/tmp/$cluster_id/config.tf"
  cd "/tmp/$cluster_id" || exit 1

  # ─── Azure-specific retry logic ───
  if [[ "$RETRY_DESTROY" == "true" ]]; then
    # Delete all resource groups older than $MIN_AGE_IN_HOURS hours
    for rg in $(az graph query -q "
        ResourceContainers
        | where type == 'microsoft.resources/subscriptions/resourcegroups'
        | where createdTime < ago(${MIN_AGE_IN_HOURS}h)
        | project name
    " -o tsv); do
      az group delete --name "$rg" --yes --no-wait
    done
  else
    # run init again later, before destroy()
    :
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
  echo "Deleting s3://$BUCKET/$cluster_folder"
  aws s3 rm "s3://$BUCKET/$cluster_folder" --recursive || return 1
  aws s3api delete-object --bucket "$BUCKET" --key "$cluster_folder/" || return 1

  cd - >/dev/null || exit 1
  rm -rf "/tmp/$cluster_id"
}

# Gather all state files from S3
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive)
aws_exit_code=$?

# Do not fail if no objects are found
if [ $aws_exit_code -ne 0 ] && [ -n "$KEY_PREFIX" ]; then
  echo "Warning: No objects found under prefix '$KEY_PREFIX'."
  echo "No matching clusters found; nothing to do."
  exit 0
fi

# Filter cluster IDs
if [ "$ID_OR_ALL" == "all" ]; then
  clusters=$(echo "$all_objects" | awk '{print $NF}' \
    | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p')
else
  clusters=$(echo "$all_objects" | awk '{print $NF}' \
    | grep "tfstate-$ID_OR_ALL/" \
    | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p')
fi

if [ -z "$clusters" ]; then
  echo "No matching clusters found; nothing to do."
  exit 0
fi

current_timestamp=$($date_command +%s)

# Prepare logs directory
log_dir="./logs"
mkdir -p "$log_dir"

# Launch destroys in parallel
pids=()
for cluster_id in $clusters; do
  log_file="$log_dir/$cluster_id.log"

  (
    cluster_folder="tfstate-$cluster_id"
    echo "[$cluster_id] Checking last modified for ${cluster_id}.tfstate..."

    last_modified=$(aws s3api head-object \
      --bucket "$BUCKET" \
      --key "$KEY_PREFIX$cluster_folder/${cluster_id}.tfstate" \
      --query 'LastModified' --output text)
    if [ -z "$last_modified" ]; then
      echo "[$cluster_id] ERROR: Could not fetch LastModified"
      exit 1
    fi

    last_ts=$($date_command -d "$last_modified" +%s)
    age_hours=$(( (current_timestamp - last_ts) / 3600 ))
    echo "[$cluster_id] Last modified: $last_modified ($age_hours hours ago)"

    if [ $age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
      echo "[$cluster_id] Destroying..."
      if ! destroy_cluster "$KEY_PREFIX$cluster_folder/${cluster_id}.tfstate"; then
        echo "[$cluster_id] ERROR during destroy"
        exit 1
      fi
      echo "[$cluster_id] Destroy succeeded"
    else
      echo "[$cluster_id] Skipping (only $age_hours hours old)"
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

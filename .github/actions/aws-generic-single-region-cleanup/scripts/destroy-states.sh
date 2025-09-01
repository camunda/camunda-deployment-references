#!/bin/bash

set -o pipefail

# Description:
# This script performs a Terraform destroy operation for tf states defined in an S3 bucket.
# It copies a dummy config.tf, initializes Terraform with
# the appropriate backend configuration, and runs `terraform destroy`. If the destroy operation
# is successful, it removes the corresponding S3 objects.
#
# Additionally, if the environment variable `RETRY_DESTROY` is set, the script will invoke `cloud-nuke`
# to ensure the deletion of any remaining VPC resources that might not have been removed by Terraform.
#
# ATTENTION: This script will be able to delete any state file in the specified S3 bucket.
# Be careful with `all` without using a prefix
#
# Usage:
# ./destroy_states.sh <BUCKET> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX] [--fail-on-not-found]
#
# Arguments:
#   BUCKET: The name of the S3 bucket containing the state files.
#   MIN_AGE_IN_HOURS: The minimum age (in hours) of states to be destroyed.
#   ID_OR_ALL: The specific ID suffix to filter objects, or "all" to destroy all objects.
#   KEY_PREFIX (optional): A prefix (with a '/' at the end) for filtering objects in the S3 bucket.
#   --fail-on-not-found (optional): If set, the script will exit with an error when no matching object is found (only when ID_OR_ALL is not "all").
#
# Example:
# ./destroy_states.sh tests-ra-aws-rosa-hcp-tf-state-eu-central-1 24 all
# ./destroy_states.sh tests-ra-aws-rosa-hcp-tf-state-eu-central-1 24 eks-state-2883
# ./destroy_states.sh tests-ra-aws-rosa-hcp-tf-state-eu-central-1 24 all aws/compute/ec2-single-region/8.7/
#
# Requirements:
# - AWS CLI installed and configured with the necessary permissions to access and modify the S3 bucket.
# - Terraform installed and accessible in the PATH.
# - `yq` installed when you use `RETRY_DESTROY`.

# Check for required arguments
if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
  echo "Usage: $0 <BUCKET> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX] [--fail-on-not-found]"
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

# Detect operating system and set the appropriate date command
if [[ "$(uname)" == "Darwin" ]]; then
    date_command="gdate"
else
    date_command="date"
fi

# Function to perform terraform destroy
destroy_state() {
  local key=$1
  local id=$2

  mkdir -p "/tmp/$id"
  cp "$SCRIPT_DIR/config" "/tmp/$id/config.tf"
  cd "/tmp/$id" || exit 1

  if [[ "$RETRY_DESTROY" == "true" ]]; then
      echo "Performing cloud-nuke on VPC to ensure that resources managed outside of Terraform are deleted."
      yq eval ".VPC.include.names_regex = [\"^$id.*\"]" -i "$SCRIPT_DIR/matching-vpc.yml"
      cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$AWS_REGION" --force
  fi

  echo "tf state: bucket=$BUCKET key=$key region=$AWS_S3_REGION"

  if ! terraform init -backend-config="bucket=$BUCKET" -backend-config="key=$key" -backend-config="region=$AWS_S3_REGION"; then return 1; fi

  if ! terraform destroy -auto-approve; then return 1; fi

  # Cleanup S3
  echo "Deleting s3://$BUCKET/$key"
  if ! aws s3 rm "s3://$BUCKET/$key"; then return 1; fi

  cd - || exit 1
  rm -rf "/tmp/$id"
}

# List objects in the S3 bucket and parse the state IDs
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive)
aws_exit_code=$?

# don't fail on folder absent
if [ $aws_exit_code -ne 0 ] && [ "$all_objects" != "" ]; then
  echo "Error executing the aws s3 ls command (Exit Code: $aws_exit_code):" >&2
  exit 1
fi

if [ "$ID_OR_ALL" == "all" ]; then
  states=$(echo "$all_objects" | awk '{print $NF}')
else
  states=$(echo "$all_objects" | awk '{print $NF}' | grep "tfstate-$ID_OR_ALL/")

  if [ -z "$states" ] && [ "$FAIL_ON_NOT_FOUND" = true ]; then
    echo "Error: No object found for ID '$ID_OR_ALL'"
    exit 1
  fi
fi

if [ -z "$states" ]; then
  echo "No objects found in the S3 bucket. Exiting script." >&2
  exit 0
fi

current_timestamp=$($date_command +%s)

pids=()
log_dir="./logs"
mkdir -p "$log_dir"

for state_path in $states; do
  state_id=$(echo "$state_path" | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p')

  log_file="$log_dir/$state_id.log"

  (
    echo "[$state_id] Checking state $state_id"

    last_modified=$(aws s3api head-object --bucket "$BUCKET" --key "$state_path" --output json | grep LastModified | awk -F '"' '{print $4}')
    if [ -z "$last_modified" ]; then
      echo "[$state_id] Error: Failed to retrieve last modified timestamp for state $state_path"
      exit 1
    fi

    last_modified_timestamp=$($date_command -d "$last_modified" +%s)
    if [ -z "$last_modified_timestamp" ]; then
      echo "[$state_id] Error: Failed to convert last modified timestamp to seconds since epoch for state $state_path"
      exit 1
    fi
    echo "[$state_id] state $state_path last modification: $last_modified ($last_modified_timestamp)"

    file_age_hours=$(( (current_timestamp - last_modified_timestamp) / 3600 ))
    if [ -z "$file_age_hours" ]; then
      echo "[$state_id] Error: Failed to calculate file age in hours for state $state_path"
      exit 1
    fi
    echo "[$state_id] state $state_path is $file_age_hours hours old"

    if [ $file_age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
      echo "[$state_id] Destroying state $state_path"

      if ! destroy_state "$state_path" "$state_id"; then
        echo "[$state_id] Error destroying state $state_path"
        exit 1
      fi
    else
      echo "[$state_id] Skipping state $state_path as it does not meet the minimum age requirement of $MIN_AGE_IN_HOURS hours"
    fi
  ) >"$log_file" 2>&1 &

  pids+=($!)
done

# Start tail -f in background
{
  echo "=== Live logs ==="
  tail -n 0 -f "$log_dir"/*.log &
  tail_pid=$!
} 2>/dev/null

# Wait and track exit codes
FAILED=0
for pid in "${pids[@]}"; do
  wait "$pid" || FAILED=1
done

# Stop tail once all processes are done
kill "$tail_pid" 2>/dev/null

# Exit with the appropriate status
if [ $FAILED -ne 0 ]; then
  echo "One or more operations failed."
  exit 1
else
  echo "All operations completed successfully."
  exit 0
fi

#!/bin/bash

set -o pipefail

# Description:
# This script performs a Terraform destroy operation for clusters defined in an S3 bucket.
# It copies the Terraform module directory to a temporary location, initializes Terraform with
# the appropriate backend configuration, and runs `terraform destroy`. If the destroy operation
# is successful, it removes the corresponding S3 objects.
#
# Additionally, if the environment variable `RETRY_DESTROY` is set, the script will invoke `cloud-nuke`
# to ensure the deletion of any remaining VPC resources that might not have been removed by Terraform.
#
# Usage:
# ./destroy_clusters.sh <BUCKET> <MODULES_DIR> <TEMP_DIR_PREFIX> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX] [--fail-on-not-found]
#
# Arguments:
#   BUCKET: The name of the S3 bucket containing the cluster state files.
#   MODULES_DIR: The directory containing the Terraform modules.
#   TEMP_DIR_PREFIX: The prefix for the temporary directories created for each cluster.
#   MIN_AGE_IN_HOURS: The minimum age (in hours) of clusters to be destroyed.
#   ID_OR_ALL: The specific ID suffix to filter objects, or "all" to destroy all objects.
#   KEY_PREFIX (optional): A prefix (with a '/' at the end) for filtering objects in the S3 bucket.
#   --fail-on-not-found (optional): If set, the script will exit with an error when no matching object is found (only when ID_OR_ALL is not "all").
#
# Example:
# ./destroy_clusters.sh tf-state-rosa-ci-eu-west-3 ./modules/rosa-hcp/ /tmp/rosa/ 24 all
# ./destroy_clusters.sh tf-state-rosa-ci-eu-west-3 ./modules/rosa-hcp/ /tmp/rosa/ 24 rosa-cluster-2883
# ./destroy_clusters.sh tf-state-rosa-ci-eu-west-3 ./modules/rosa-hcp/ /tmp/rosa/ 24 all my-prefix/
#
# Requirements:
# - AWS CLI installed and configured with the necessary permissions to access and modify the S3 bucket.
# - Terraform installed and accessible in the PATH.
# - `yq` installed when you use `RETRY_DESTROY`.

# Check for required arguments
if [ "$#" -lt 5 ] || [ "$#" -gt 7 ]; then
  echo "Usage: $0 <BUCKET> <MODULES_DIR> <TEMP_DIR_PREFIX> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [KEY_PREFIX] [--fail-on-not-found]"
  exit 1
fi

# Check if required environment variables are set
if [ -z "$RHCS_TOKEN" ]; then
  echo "Error: The environment variable RHCS_TOKEN is not set."
  exit 1
fi

if [ -z "$AWS_REGION" ]; then
  echo "Error: The environment variable AWS_REGION is not set."
  exit 1
fi

# Variables
BUCKET=$1
MODULES_DIR=$2
TEMP_DIR_PREFIX=$3
MIN_AGE_IN_HOURS=$4
ID_OR_ALL=$5
KEY_PREFIX=""
FAILED=0
CURRENT_DIR=$(pwd)
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
AWS_S3_REGION=${AWS_S3_REGION:-$AWS_REGION}
FAIL_ON_NOT_FOUND=false

# Handle optional KEY_PREFIX and flag
for arg in "${@:6}"; do
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
destroy_cluster() {
  local cluster_id=$1
  local cluster_folder="$KEY_PREFIX$2"
  # we must add two levels to replicate the "source = ../../modules" relative path presented in the module
  local temp_dir="${TEMP_DIR_PREFIX}${cluster_id}/1/2"
  local temp_generic_modules_dir="${TEMP_DIR_PREFIX}${cluster_id}/modules/"
  local source_generic_modules="$MODULES_DIR/../../modules/"

  echo "Copying generic modules $source_generic_modules in $temp_generic_modules_dir"

  mkdir -p "$temp_generic_modules_dir" || return 1
  cp -a "$source_generic_modules." "$temp_generic_modules_dir" || return 1

  tree "$source_generic_modules" "$temp_generic_modules_dir" || return 1

  echo "Copying $MODULES_DIR in $temp_dir"

  mkdir -p "$temp_dir" || return 1
  cp -a "$MODULES_DIR." "$temp_dir" || return 1

  tree "$MODULES_DIR" "$temp_dir" || return 1

  if [[ "$RETRY_DESTROY" == "true" ]]; then
      echo "Performing cloud-nuke on VPC to ensure that resources managed outside of Terraform are deleted."
      yq eval ".VPC.include.names_regex = [\"^$cluster_id.*\"]" -i "$SCRIPT_DIR/matching-vpc.yml"
      cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$AWS_REGION" --force
  fi

  cd "$temp_dir" || return 1

  tree "." || return 1

  echo "tf state: bucket=$BUCKET key=${cluster_folder}/${cluster_id}.tfstate region=$AWS_S3_REGION"

  if ! terraform init -backend-config="bucket=$BUCKET" -backend-config="key=${cluster_folder}/${cluster_id}.tfstate" -backend-config="region=$AWS_S3_REGION"; then return 1; fi

  # Edit the name of the cluster
  sed -i -e "s/\(rosa_cluster_name\s*=\s*\"\)[^\"]*\(\"\)/\1${cluster_id}\2/" cluster.tf

  echo "Destroying cluster"
  if ! output_tf_destroy=$(terraform destroy -auto-approve 2>&1); then
    echo "$output_tf_destroy"

    if [[ "$output_tf_destroy" == *"CLUSTERS-MGMT-404"* ]]; then
      echo "The cluster appears to have already been deleted (error: CLUSTERS-MGMT-404). Considering the deletion successful (likely due to cloud-nuke)."
    else
      echo "Error destroying module cluster in group"
      return 1
    fi
  fi


  # Cleanup S3
  echo "Deleting s3://$BUCKET/$cluster_folder"
  if ! aws s3 rm "s3://$BUCKET/$cluster_folder" --recursive; then return 1; fi
  if ! aws s3api delete-object --bucket "$BUCKET" --key "$cluster_folder/"; then return 1; fi

  cd - || return 1
  rm -rf "$temp_dir" || return 1
}

# List objects in the S3 bucket and parse the cluster IDs
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX")
aws_exit_code=$?

# don't fail on folder absent
if [ $aws_exit_code -ne 0 ] && [ "$all_objects" != "" ]; then
  echo "Error executing the aws s3 ls command (Exit Code: $aws_exit_code):" >&2
  exit 1
fi

if [ "$ID_OR_ALL" == "all" ]; then
  clusters=$(echo "$all_objects" | awk '{print $2}' | sed -n 's#^tfstate-\(.*\)/$#\1#p')
else
  clusters=$(echo "$all_objects" | awk '{print $2}' | grep "tfstate-$ID_OR_ALL/" | sed -n 's#^tfstate-\(.*\)/$#\1#p')

  if [ -z "$clusters" ] && [ "$FAIL_ON_NOT_FOUND" = true ]; then
    echo "Error: No object found for ID '$ID_OR_ALL'"
    exit 1
  fi
fi

if [ -z "$clusters" ]; then
  echo "No objects found in the S3 bucket. Exiting script." >&2
  exit 0
fi

current_timestamp=$($date_command +%s)

pids=()
log_dir="./logs"
mkdir -p "$log_dir"

for cluster_id in $clusters; do
  log_file="$log_dir/$cluster_id.log"

  (
    cd "$CURRENT_DIR" || return 1


    cluster_folder="tfstate-$cluster_id"
    echo "[$cluster_id] Checking cluster $cluster_id in $cluster_folder"

    last_modified=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY_PREFIX$cluster_folder/${cluster_id}.tfstate" --output json | grep LastModified | awk -F '"' '{print $4}')
    if [ -z "$last_modified" ]; then
      echo "[$cluster_id] Error: Failed to retrieve last modified timestamp for cluster $cluster_id"
      exit 1
    fi

    last_modified_timestamp=$($date_command -d "$last_modified" +%s)
    if [ -z "$last_modified_timestamp" ]; then
      echo "[$cluster_id] Error: Failed to convert last modified timestamp to seconds since epoch for cluster $cluster_id"
      exit 1
    fi
    echo "[$cluster_id] Cluster $cluster_id last modification: $last_modified ($last_modified_timestamp)"

    file_age_hours=$(( (current_timestamp - last_modified_timestamp) / 3600 ))
    if [ -z "$file_age_hours" ]; then
      echo "[$cluster_id] Error: Failed to calculate file age in hours for cluster $cluster_id"
      exit 1
    fi
    echo "[$cluster_id] Cluster $cluster_id is $file_age_hours hours old"

    if [ $file_age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
      echo "[$cluster_id] Destroying cluster $cluster_id in $cluster_folder"

      if ! destroy_cluster "$cluster_id" "$cluster_folder"; then
        echo "[$cluster_id] Error destroying cluster $cluster_id"
        FAILED=1
      fi
    else
      echo "[$cluster_id] Skipping cluster $cluster_id as it does not meet the minimum age requirement of $MIN_AGE_IN_HOURS hours"
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

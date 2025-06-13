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
destroy_resource() {
  local group_id=$1
  local module_name=$2
  local module_folder="${KEY_PREFIX}tfstate-${group_id}"
  local module_tfstate="${module_folder}/${module_name}.tfstate"

  # Create temporary directories for Terraform execution
  local temp_dir="${TEMP_DIR_PREFIX}${group_id}/1/2/3/${module_name}/"
  local temp_generic_modules_dir="${TEMP_DIR_PREFIX}${group_id}/modules/"
  local source_generic_modules="$MODULES_DIR/../../../modules/"

  echo "Copying generic modules from $source_generic_modules to $temp_generic_modules_dir"
  mkdir -p "$temp_generic_modules_dir" || return 1
  cp -a "$source_generic_modules." "$temp_generic_modules_dir" || return 1
  tree "$source_generic_modules" "$temp_generic_modules_dir" || return 1

  real_module_dir="${MODULES_DIR}${module_name}/"

  echo "Copying $real_module_dir to $temp_dir"
  mkdir -p "$temp_dir" || return 1
  cp -a "$real_module_dir." "$temp_dir" || return 1
  tree "$real_module_dir" "$temp_dir" || return 1

  cd "$temp_dir" || return 1
  tree "." || return 1

  if  [[ "$module_name" == "cluster" ]]; then

    if [[ "$RETRY_DESTROY" == "true" ]]; then
        echo "Performing cloud-nuke on VPC to ensure that resources managed outside of Terraform are deleted."
        yq eval ".VPC.include.names_regex = [\"^$group_id.*\"]" -i "$SCRIPT_DIR/matching-vpc.yml"
        cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$AWS_REGION" --force
    fi

    echo "Updating cluster name in Terraform configuration..."

    sed -i -e "s/\(rosa_cluster_name\s*=\s*\"\)[^\"]*\(\"\)/\1${group_id}\2/" cluster.tf
  elif [[ "$module_name" == "vpn" ]]; then
    echo "Setting values for VPN variables..."

    export TF_VAR_s3_bucket_region="$VPN_S3_BUCKET_REGION"

    TF_VAR_vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${group_id}*" --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION")

    if [[ "$TF_VAR_vpc_id" == "None" || -z "$TF_VAR_vpc_id" ]]; then
      echo "Error: VPC = $TF_VAR_vpc_id not found."

      echo "Assuming it was deleted by Cloud Nuke. Cleaning up Terraform state..."
      aws s3 rm "s3://$BUCKET/$module_tfstate" --recursive || return 1
      aws s3api delete-object --bucket "$BUCKET" --key "$module_tfstate" || return 1
      cd - || return 1
      rm -rf "$temp_dir" || return 1

      return 0
    fi

    export TF_VAR_vpc_id
  fi


  echo "Initializing Terraform for module $module_name (tfstate: $module_tfstate)"

  if ! terraform init -backend-config="bucket=$BUCKET" -backend-config="key=$module_tfstate" -backend-config="region=$AWS_S3_REGION"; then
    echo "Error initializing Terraform for module $module_name in group $group_id"
    return 1
  fi

  echo "Destroying module $module_name in group $group_id"
  if ! output_tf_destroy=$(terraform destroy -auto-approve 2>&1); then
    echo "$output_tf_destroy"

    if [[ "$module_name" == "cluster" && "$output_tf_destroy" == *"CLUSTERS-MGMT-404"* ]]; then
      echo "The cluster appears to have already been deleted (error: CLUSTERS-MGMT-404). Considering the deletion successful (likely due to cloud-nuke)."
    else
      echo "Error destroying module $module_name in group $group_id"
      return 1
    fi
  fi

  # Cleanup S3 resources
  echo "Deleting S3 resources for module $module_name in group $group_id (tfstate=s3://$BUCKET/$module_tfstate)"
  if ! aws s3 rm "s3://$BUCKET/$module_tfstate" --recursive; then return 1; fi
  if ! aws s3api delete-object --bucket "$BUCKET" --key "$module_tfstate"; then return 1; fi

  cd - || return 1
  rm -rf "$temp_dir" || return 1

  echo "Successfully destroyed module $module_name in group $group_id"
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
  groups=$(echo "$all_objects" | awk '{print $2}' | sed -n 's#^tfstate-\(.*\)/$#\1#p')
else
  groups=$(echo "$all_objects" | awk '{print $2}' | grep "tfstate-$ID_OR_ALL/" | sed -n 's#^tfstate-\(.*\)/$#\1#p')

  if [ -z "$groups" ] && [ "$FAIL_ON_NOT_FOUND" = true ]; then
    echo "Error: No object found for ID '$ID_OR_ALL'"
    exit 1
  fi
fi

if [ -z "$groups" ]; then
  echo "No objects found in the S3 bucket. Exiting script." >&2
  exit 0
fi

current_timestamp=$($date_command +%s)

pids=()
log_dir="./logs"
mkdir -p "$log_dir"

for group_id in $groups; do
  log_file="$log_dir/$group_id.log"

  (
    cd "$CURRENT_DIR" || return 1

    echo "[$group_id] Processing group: $group_id"
    module_order=("vpn" "cluster")
    group_folder="${KEY_PREFIX}tfstate-$group_id/"

    for module_name in "${module_order[@]}"; do
      module_path="${group_folder}${module_name}.tfstate"

      # Check if the module exists
      if ! aws s3 ls "s3://$BUCKET/$module_path" >/dev/null 2>&1; then
        echo "[$group_id] Module $module_name not found for group $group_id, skipping..."
        continue
      fi

      last_modified=$(aws s3api head-object --bucket "$BUCKET" --key "$module_path" --output json | grep LastModified | awk -F '"' '{print $4}')
      if [ -z "$last_modified" ]; then
        echo "[$group_id] Warning: Could not retrieve last modified timestamp for $module_path, skipping."
        continue
      fi

      last_modified_timestamp=$($date_command -d "$last_modified" +%s)
      if [ -z "$last_modified_timestamp" ]; then
        echo "[$group_id] Error: Failed to convert last modified timestamp for $module_path"
        exit 1
      fi
      echo "[$group_id] Module $module_name last modified: $last_modified ($last_modified_timestamp)"

      file_age_hours=$(( (current_timestamp - last_modified_timestamp) / 3600 ))
      if [ -z "$file_age_hours" ]; then
        echo "[$group_id] Error: Failed to calculate file age in hours for $module_path"
        exit 1
      fi
      echo "[$group_id] Module $module_name is $file_age_hours hours old"

      if [ $file_age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
        echo "[$group_id] Destroying module $module_name in group $group_id"

        if ! destroy_resource "$group_id" "$module_name"; then
          echo "[$group_id] Error destroying module $module_name in group $group_id"
          exit 1
        fi
      else
        echo "[$group_id] Skipping $module_name as it does not meet the minimum age requirement of $MIN_AGE_IN_HOURS hours"
      fi
    done
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

# Function to check if a folder is empty
is_empty_folder() {
    local folder="$1"
    # List all objects within the folder (excluding subfolders) and count them
    local file_count
    if ! file_count=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX$folder" --recursive | grep -cv '/$')
    then
        echo "Error listing contents of s3://$BUCKET/$KEY_PREFIX$folder"
        exit 1
    fi

    # Return true if the folder is empty
    [ "$file_count" -eq "0" ]
}

# Function to list and process all empty folders
process_empty_folders() {
    local empty_folders_found=false

    # List all folders and sort them from the deepest to the shallowest
    if ! empty_folders=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive | awk '{print $4}' | grep '/$' | sort -r)
    then
        echo "Error listing folders in s3://$BUCKET/$KEY_PREFIX"
        exit 1
    fi

    # Process each folder
    for folder in $empty_folders; do
        if is_empty_folder "$folder"; then
            # If the folder is empty, delete it
            if ! aws s3 rm "s3://$BUCKET/$KEY_PREFIX$folder" --recursive
            then
                echo "Error deleting folder: s3://$BUCKET/$KEY_PREFIX$folder"
                exit 1
            else
                echo "Deleted empty folder: s3://$BUCKET/$KEY_PREFIX$folder"
                empty_folders_found=true
            fi
        fi
    done

    echo $empty_folders_found
}

echo "Cleaning up empty folders in s3://$BUCKET/$KEY_PREFIX"
# Loop until no empty folders are found
while true; do
    # Process folders and check if any empty folders were found and deleted
    if [ "$(process_empty_folders)" = true ]; then
        echo "Rechecking for empty folders..."
    else
        echo "No more empty folders found."
        break
    fi
done

# Exit with the appropriate status
if [ $FAILED -ne 0 ]; then
  echo "One or more operations failed."
  exit 1
else
  echo "All operations completed successfully."
  exit 0
fi
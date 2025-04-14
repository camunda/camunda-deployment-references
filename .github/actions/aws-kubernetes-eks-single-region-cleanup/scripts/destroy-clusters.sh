#!/bin/bash

set -o pipefail

# Description:
# This script performs a Terraform destroy operation for clusters defined in an S3 bucket.
# It copies a dummy config.tf, initializes Terraform with
# the appropriate backend configuration, and runs `terraform destroy`. If the destroy operation
# is successful, it removes the corresponding S3 objects.
#
# Additionally, if the environment variable `RETRY_DESTROY` is set, the script will invoke `cloud-nuke`
# to ensure the deletion of any remaining VPC resources that might not have been removed by Terraform.
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
# - `yq` installed when you use `RETRY_DESTROY`.

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
KEY_PREFIX=${4:-""}  # Key prefix is optional
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

  if [[ "$RETRY_DESTROY" == "true" ]]; then
      echo "Performing cloud-nuke on VPC to ensure that resources managed outside of Terraform are deleted."
      yq eval ".VPC.include.names_regex = [\"^$cluster_id.*\"]" -i "$SCRIPT_DIR/matching-vpc.yml"
      cloud-nuke aws --config "$SCRIPT_DIR/matching-vpc.yml" --resource-type vpc --region "$AWS_REGION" --force
  fi

  echo "tf state: bucket=$BUCKET key=$key region=$AWS_S3_REGION"

  if ! terraform init -backend-config="bucket=$BUCKET" -backend-config="key=$key" -backend-config="region=$AWS_S3_REGION"; then return 1; fi

  # Since we use a blank config.tf, we need to remove the default storage class as it otherwise it's blocking
  # This is due to the k8s provider not being configured
  terraform state rm 'module.eks_cluster.kubernetes_storage_class_v1.ebs_sc[0]'

  if ! terraform destroy -auto-approve; then return 1; fi

  # Cleanup S3
  echo "Deleting s3://$BUCKET/$cluster_folder"
  if ! aws s3 rm "s3://$BUCKET/$cluster_folder" --recursive; then return 1; fi
  if ! aws s3api delete-object --bucket "$BUCKET" --key "$cluster_folder/"; then return 1; fi

  cd - || exit 1
  rm -rf "/tmp/$cluster_id"
}

# List objects in the S3 bucket and parse the cluster IDs
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive)
aws_exit_code=$?

# don't fail on folder absent
if [ $aws_exit_code -ne 0 ] && [ "$all_objects" != "" ]; then
  echo "Error executing the aws s3 ls command (Exit Code: $aws_exit_code):" >&2
  exit 1
fi

if [ "$ID_OR_ALL" == "all" ]; then
  clusters=$(echo "$all_objects" | awk '{print $NF}' | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p')
else
  clusters=$(echo "$all_objects" | awk '{print $NF}' | grep "tfstate-$ID_OR_ALL/" | sed -n 's#.*/tfstate-\([^/]*\)/.*#\1#p')
fi

if [ -z "$clusters" ]; then
  echo "No objects found in the S3 bucket. Exiting script." >&2
  exit 0
fi

current_timestamp=$($date_command +%s)

for cluster_id in $clusters; do
  cluster_folder="tfstate-$cluster_id"
  echo "Checking cluster $cluster_id in $cluster_folder"

  last_modified=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY_PREFIX$cluster_folder/${cluster_id}.tfstate" --output json | grep LastModified | awk -F '"' '{print $4}')
  if [ -z "$last_modified" ]; then
    echo "Error: Failed to retrieve last modified timestamp for cluster $cluster_id"
    exit 1
  fi

  last_modified_timestamp=$($date_command -d "$last_modified" +%s)
  if [ -z "$last_modified_timestamp" ]; then
    echo "Error: Failed to convert last modified timestamp to seconds since epoch for cluster $cluster_id"
    exit 1
  fi
  echo "Cluster $cluster_id last modification: $last_modified ($last_modified_timestamp)"

  file_age_hours=$(( (current_timestamp - last_modified_timestamp) / 3600 ))
  if [ -z "$file_age_hours" ]; then
    echo "Error: Failed to calculate file age in hours for cluster $cluster_id"
    exit 1
  fi
  echo "Cluster $cluster_id is $file_age_hours hours old"

  if [ $file_age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
    echo "Destroying cluster $cluster_id in $cluster_folder"

    if ! destroy_cluster "$KEY_PREFIX$cluster_folder/${cluster_id}.tfstate"; then
      echo "Error destroying cluster $cluster_id"
      FAILED=1
    fi
  else
    echo "Skipping cluster $cluster_id as it does not meet the minimum age requirement of $MIN_AGE_IN_HOURS hours"
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

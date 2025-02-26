#!/bin/bash

set -o pipefail

# Description:
# This script performs a Terraform destroy operation for resources defined in an S3 bucket.
# It copies the Terraform module directory to a temporary location, initializes Terraform with
# the appropriate backend configuration, and runs `terraform destroy`. If the destroy operation
# is successful, it removes the corresponding S3 objects.
#
# Usage:
# ./destroy.sh <BUCKET> <MODULES_DIR> <TEMP_DIR_PREFIX> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [MODULE_NAME]
#
# Arguments:
#   BUCKET: The name of the S3 bucket containing the resource state files.
#   MODULES_DIR: The directory containing the Terraform modules.
#   TEMP_DIR_PREFIX: The prefix for the temporary directories created for each resource.
#   MIN_AGE_IN_HOURS: The minimum age (in hours) of resources to be destroyed.
#   ID_OR_ALL: The specific ID suffix to filter objects, or "all" to destroy all objects.
#   MODULE_NAME (optional): The name of the module to destroy (e.g., "eks-cluster", "aurora", "opensearch"). Default is "all".
#
# Example:
# ./destroy.sh tf-state-eks-ci-eu-west-3 ./modules/eks/ /tmp/eks/ 24 all
# ./destroy.sh tf-state-eks-ci-eu-west-3 ./modules/eks/ /tmp/eks/ 24 4891048 eks-cluster
#
# Requirements:
# - AWS CLI installed and configured with the necessary permissions to access and modify the S3 bucket.
# - Terraform installed and accessible in the PATH.

# Check for required arguments
if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
  echo "Usage: $0 <BUCKET> <MODULES_DIR> <TEMP_DIR_PREFIX> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [MODULE_NAME]"
  exit 1
fi

if [ -z "$AWS_REGION" ]; then
  echo "Error: The environment variable AWS_REGION is not set."
  exit 1
fi

# Detect operating system and set the appropriate date command
if [[ "$(uname)" == "Darwin" ]]; then
    date_command="gdate"
else
    date_command="date"
fi

# Variables
BUCKET=$1
MODULES_DIR=$2
TEMP_DIR_PREFIX=$3
MIN_AGE_IN_HOURS=$4
ID_OR_ALL=$5
MODULE_NAME=${6:-all}
FAILED=0
CURRENT_DIR=$(pwd)
AWS_S3_REGION=${AWS_S3_REGION:-$AWS_REGION}

# Function to check if a folder is empty
is_empty_folder() {
    local folder="$1"
    # List all objects within the folder (excluding subfolders) and count them
    local file_count
    file_count=$(aws s3 ls "s3://$BUCKET/$folder" --recursive | grep -v '/$' | wc -l)

    # Check if the command succeeded
    if [ $? -ne 0 ]; then
        echo "Error listing contents of s3://$BUCKET/$folder"
        exit 1
    fi

    # Return true if the folder is empty
    [ "$file_count" -eq "0" ]
}

# Function to list and process all empty folders
process_empty_folders() {
    local empty_folders_found=false

    # List all folders and sort them from the deepest to the shallowest
    empty_folders=$(aws s3 ls "s3://$BUCKET/" --recursive | awk '{print $4}' | grep '/$' | sort -r)

    # Check if the command succeeded
    if [ $? -ne 0 ]; then
        echo "Error listing folders in s3://$BUCKET/"
        exit 1
    fi

    # Process each folder
    for folder in $empty_folders; do
        if is_empty_folder "$folder"; then
            # If the folder is empty, delete it
            aws s3 rm "s3://$BUCKET/$folder" --recursive

            # Check if the deletion command succeeded
            if [ $? -ne 0 ]; then
                echo "Error deleting folder: s3://$BUCKET/$folder"
                exit 1
            else
                echo "Deleted empty folder: s3://$BUCKET/$folder"
                empty_folders_found=true
            fi
        fi
    done

    echo $empty_folders_found
}

# Function to perform terraform destroy
destroy_resource() {
  local resource_id=$1
  local terraform_module=$2
  local cluster_name=$3
  local resource_id_dir
  resource_id_dir=$(dirname "$resource_id")
  local temp_dir="${TEMP_DIR_PREFIX}${resource_id_dir}"
  local resource_module_path="$MODULES_DIR$terraform_module/"

  echo "Copying $resource_module_path in $temp_dir"

  mkdir -p "$temp_dir" || return 1
  cp -a "$resource_module_path." "$temp_dir" || return 1

  echo "Copying backend.tf in $temp_dir"
  cp "${MODULES_DIR}fixtures/backend.tf" "$temp_dir/backend.tf" || return 1

  tree "$resource_module_path" "$temp_dir" || return 1

  cd "$temp_dir" || return 1

  tree "." || return 1

  echo "tf state: bucket=$BUCKET key=${resource_id} region=$AWS_S3_REGION"

  if ! terraform init -backend-config="bucket=$BUCKET" -backend-config="key=${resource_id}" -backend-config="region=$AWS_S3_REGION"; then return 1; fi

  # Execute the terraform destroy command with appropriate variables (see https://github.com/hashicorp/terraform/issues/23552)
  if [ "$terraform_module" == "eks-cluster" ]; then
    terraform state rm "kubernetes_storage_class_v1.ebs_sc" || true

    VPC_ID=$(terraform output -raw vpc_id)

    if ! terraform destroy -auto-approve \
      -var="region=$AWS_REGION" \
      -var="name=$cluster_name" \
      -var="cluster_service_ipv4_cidr=10.190.0.0/16" \
      -var="cluster_node_ipv4_cidr=10.192.0.0/16"; then
        echo "Error destroying EKS cluster $cluster_name"

        export AWS_PAGER=""
        echo "Checking subnetes for $VPC_ID"
        aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"
        echo "Checking route tables for $VPC_ID"
        aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID"
        echo "Checking internet gateways for $VPC_ID"
        aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID"
        echo "Checking NAT gateways for $VPC_ID"
        aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID"
        echo "Dumping elastic ips"
        aws ec2 describe-addresses

        return 1
      fi

  elif [ "$terraform_module" == "aurora" ]; then
    if ! terraform destroy -auto-approve \
      -var="cluster_name=$cluster_name" \
      -var="username=dummy" \
      -var="password=dummy" \
      -var="subnet_ids=[]" \
      -var="cidr_blocks=[]" \
      -var="vpc_id=vpc-dummy"; then return 1; fi

  elif [ "$terraform_module" == "opensearch" ]; then
    if ! terraform destroy -auto-approve \
      -var="domain_name=$cluster_name" \
      -var="vpc_id=vpc-dummy" \
      -var="advanced_security_master_user_password=dummy" \
      -var="vpc_id=vpc-dummy" \
      -var="cidr_blocks=[]" \
      -var="subnet_ids=[]"; then return 1; fi

  else
    echo "Unsupported module: $terraform_module"
    return 1
  fi

  # Cleanup S3
  echo "Deleting s3://$BUCKET/$resource_id"
  if ! aws s3 rm "s3://$BUCKET/$resource_id" --recursive; then return 1; fi
  if ! aws s3api delete-object --bucket "$BUCKET" --key "$resource_id"; then return 1; fi

  cd - || return 1
  rm -rf "$temp_dir" || return 1
}

# List objects in the S3 bucket and parse the resource IDs
all_objects=$(aws s3 ls "s3://$BUCKET/" --recursive)
aws_exit_code=$?

if [ $aws_exit_code -ne 0 ]; then
  echo "Error executing the aws s3 ls command (Exit Code: $aws_exit_code):" >&2
  exit 1
fi

# Categorize resources by module type
if [ "$ID_OR_ALL" == "all" ]; then
  resources=$(echo "$all_objects" | grep "/terraform.tfstate" | awk '{print $4}')
else
  resources=$(echo "$all_objects" | grep "/terraform.tfstate" | grep "$ID_OR_ALL" | awk '{print $4}')
fi

# Check if resources is empty (i.e., no objects found)
if [ -z "$resources" ]; then
  echo "No terraform.tfstate objects found in the S3 bucket. Exiting script." >&2
  exit 0
fi

# Initialise arrays for the resources by module type
aurora_resources=()
opensearch_resources=()
eks_resources=()

# Classify resources into different module types
for resource_id in $resources; do
  terraform_module=$(basename "$(dirname "$resource_id")")

  case "$terraform_module" in
    aurora)
      aurora_resources+=("$resource_id")
      ;;
    opensearch)
      opensearch_resources+=("$resource_id")
      ;;
    eks-cluster)
      eks_resources+=("$resource_id")
      ;;
    *)
      echo "Skipping unsupported module: $terraform_module"
      ;;
  esac
done

current_timestamp=$($date_command +%s)

# Function to process the destruction for a specific resource type
process_resources_in_order() {
  local resources=("$@")  # Accept an array of resources to process

  for resource_id in "${resources[@]}"; do
    cd "$CURRENT_DIR" || return 1

    terraform_module=$(basename "$(dirname "$resource_id")")
    echo "Checking resource $resource_id (terraform module=$terraform_module)"

    # Apply module name filter if specified
    if [ "$MODULE_NAME" != "all" ] && [ "$MODULE_NAME" != "$terraform_module" ]; then
      echo "Skipping resource $resource_id because it does not match the specified module name: $MODULE_NAME"
      continue
    fi

    last_modified=$(aws s3api head-object --bucket "$BUCKET" --key "$resource_id" --output json | grep LastModified | awk -F '"' '{print $4}')
    if [ -z "$last_modified" ]; then
      echo "Error: Failed to retrieve last modified timestamp for resource $resource_id"
      exit 1
    fi

    last_modified_timestamp=$($date_command -d "$last_modified" +%s)
    if [ -z "$last_modified_timestamp" ]; then
      echo "Error: Failed to convert last modified timestamp to seconds since epoch for resource $resource_id"
      exit 1
    fi
    echo "Resource $resource_id last modification: $last_modified ($last_modified_timestamp)"

    file_age_hours=$(( ($current_timestamp - $last_modified_timestamp) / 3600 ))
    if [ -z "$file_age_hours" ]; then
      echo "Error: Failed to calculate file age in hours for resource $resource_id"
      exit 1
    fi
    echo "Resource $resource_id is $file_age_hours hours old"

    if [ $file_age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
      # Name of the cluster is always after terraform/
      cluster_name=$(echo "$resource_id" | cut -d'/' -f2)
      echo "Destroying resource $resource_id in $terraform_module (cluster_name=$cluster_name)"

      if ! destroy_resource "$resource_id" "$terraform_module" "$cluster_name"; then
        echo "Error destroying resource $resource_id"
        FAILED=1
      fi
    else
      echo "Skipping resource $resource_id as it does not meet the minimum age requirement of $MIN_AGE_IN_HOURS hours"
    fi
  done
}

# Destroy resources in the specific order: Aurora, OpenSearch, then EKS
echo "Destroying Aurora resources..."
process_resources_in_order "${aurora_resources[@]}"

echo "Destroying OpenSearch resources..."
process_resources_in_order "${opensearch_resources[@]}"

echo "Destroying EKS resources..."
process_resources_in_order "${eks_resources[@]}"

echo "Cleaning up empty folders in s3://$BUCKET"
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

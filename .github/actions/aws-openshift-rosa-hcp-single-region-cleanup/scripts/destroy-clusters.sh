#!/bin/bash

set -o pipefail

# Description:
# This script performs a Terraform destroy operation for clusters defined in an S3 bucket.
# It copies the Terraform module directory to a temporary location, initializes Terraform with
# the appropriate backend configuration, and runs `terraform destroy`. If the destroy operation
# is successful, it removes the corresponding S3 objects.
#
# Before `terraform destroy`, the script removes orphan AWS resources (Load Balancers,
# Security Groups, ENIs) that are created outside of Terraform by cloud providers (e.g., ROSA HCP).
# These resources can cause DependencyViolation errors during VPC deletion if not cleaned up first.
# The VPC itself is left intact for Terraform to manage.
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

# Remove cloud-provider-managed resources (Load Balancers, Security Groups, ENIs, etc.) inside a VPC.
# These are created outside of Terraform by ROSA operators, EKS ingress controllers, etc.
# The VPC itself is left intact for Terraform to manage.
# This is a best-effort cleanup: resources still in use will fail to delete and be silently skipped.
cleanup_vpc_dependencies() {
  local vpc_id=$1
  local region=$2

  echo "  Cleaning up VPC dependencies for $vpc_id in $region..."

  # 1. Delete Load Balancers (ELBv2: ALB/NLB)
  local lb_arns
  lb_arns=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerArn" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$lb_arns" && "$lb_arns" != "None" ]]; then
    for lb_arn in $lb_arns; do
      echo "  Deleting Load Balancer (v2): $lb_arn"
      aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$region" || true
    done
    echo "  Waiting for Load Balancers to deprovision..."
    sleep 30
  fi

  # 2. Delete Classic Load Balancers
  local clb_names
  clb_names=$(aws elb describe-load-balancers \
    --query "LoadBalancerDescriptions[?VPCId=='${vpc_id}'].LoadBalancerName" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$clb_names" && "$clb_names" != "None" ]]; then
    for clb_name in $clb_names; do
      echo "  Deleting Classic Load Balancer: $clb_name"
      aws elb delete-load-balancer --load-balancer-name "$clb_name" --region "$region" || true
    done
    sleep 10
  fi

  # 3. Delete NAT Gateways
  local nat_gw_ids
  nat_gw_ids=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=${vpc_id}" "Name=state,Values=available" \
    --query "NatGateways[*].NatGatewayId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$nat_gw_ids" && "$nat_gw_ids" != "None" ]]; then
    for nat_id in $nat_gw_ids; do
      echo "  Deleting NAT Gateway: $nat_id"
      aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$region" || true
    done
    echo "  Waiting for NAT Gateways to delete..."
    sleep 30
  fi

  # 4. Delete VPC Endpoints
  local vpce_ids
  vpce_ids=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query "VpcEndpoints[?State!='deleted'].VpcEndpointId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$vpce_ids" && "$vpce_ids" != "None" ]]; then
    echo "  Deleting VPC Endpoints: $vpce_ids"
    # shellcheck disable=SC2086
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $vpce_ids --region "$region" || true
  fi

  # 5. Delete non-default Security Groups
  local sg_ids
  sg_ids=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$sg_ids" && "$sg_ids" != "None" ]]; then
    for sg_id in $sg_ids; do
      echo "  Deleting Security Group: $sg_id"
      aws ec2 delete-security-group --group-id "$sg_id" --region "$region" 2>/dev/null || true
    done
  fi

  # 6. Delete detached (available) Network Interfaces
  local eni_ids
  eni_ids=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=${vpc_id}" "Name=status,Values=available" \
    --query "NetworkInterfaces[*].NetworkInterfaceId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$eni_ids" && "$eni_ids" != "None" ]]; then
    for eni_id in $eni_ids; do
      echo "  Deleting Network Interface: $eni_id"
      aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$region" 2>/dev/null || true
    done
  fi

  # 6b. Forcefully detach and delete in-use Network Interfaces (left by ROSA/EKS teardown)
  local attached_enis
  attached_enis=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=${vpc_id}" "Name=status,Values=in-use" \
    --query "NetworkInterfaces[*].[NetworkInterfaceId,Attachment.AttachmentId]" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$attached_enis" && "$attached_enis" != "None" ]]; then
    while IFS=$'\t' read -r eni_id attachment_id; do
      [[ -z "$eni_id" ]] && continue
      echo "  Detaching Network Interface: $eni_id (attachment: $attachment_id)"
      aws ec2 detach-network-interface --attachment-id "$attachment_id" --force --region "$region" 2>/dev/null || true
    done <<< "$attached_enis"
    echo "  Waiting for ENIs to detach..."
    sleep 10
    while IFS=$'\t' read -r eni_id _; do
      [[ -z "$eni_id" ]] && continue
      echo "  Deleting Network Interface: $eni_id"
      aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$region" 2>/dev/null || true
    done <<< "$attached_enis"
  fi

  # 7. Delete non-main Route Table associations and Route Tables
  local rtb_ids
  rtb_ids=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query "RouteTables[?Associations[?Main!=\`true\`]].RouteTableId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$rtb_ids" && "$rtb_ids" != "None" ]]; then
    for rtb_id in $rtb_ids; do
      local assoc_ids
      assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rtb_id" \
        --query "RouteTables[0].Associations[?Main!=\`true\`].RouteTableAssociationId" \
        --output text --region "$region" 2>/dev/null)
      for assoc_id in $assoc_ids; do
        aws ec2 disassociate-route-table --association-id "$assoc_id" --region "$region" 2>/dev/null || true
      done
      echo "  Deleting Route Table: $rtb_id"
      aws ec2 delete-route-table --route-table-id "$rtb_id" --region "$region" 2>/dev/null || true
    done
  fi

  # 8. Detach and delete Internet Gateways
  local igw_ids
  igw_ids=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${vpc_id}" \
    --query "InternetGateways[*].InternetGatewayId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$igw_ids" && "$igw_ids" != "None" ]]; then
    for igw_id in $igw_ids; do
      echo "  Detaching and deleting Internet Gateway: $igw_id"
      aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$region" 2>/dev/null || true
      aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$region" 2>/dev/null || true
    done
  fi

  # 9. Delete Subnets
  local subnet_ids
  subnet_ids=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query "Subnets[*].SubnetId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$subnet_ids" && "$subnet_ids" != "None" ]]; then
    for subnet_id in $subnet_ids; do
      echo "  Deleting Subnet: $subnet_id"
      aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$region" 2>/dev/null || true
    done
  fi

  echo "  VPC dependency cleanup completed for $vpc_id"
}

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

  # Pre-cleanup: remove cloud-provider-managed resources inside the VPC before terraform destroy.
  # ROSA HCP creates AWS resources (LBs, SGs, ENIs) outside of Terraform state management.
  # When Terraform destroys the ROSA cluster, AWS/Red Hat cleanup is asynchronous, meaning the VPC
  # may still have active dependencies when Terraform tries to delete it, causing a ~20min retry loop
  # followed by failure. We proactively remove these orphan resources while keeping the VPC intact
  # for Terraform to delete cleanly.
  local vpc_id
  vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_id}*" --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION")
  if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
      echo "[$cluster_id] Pre-cleanup: removing orphan resources in VPC $vpc_id..."
      cleanup_vpc_dependencies "$vpc_id" "$AWS_REGION"

      # On retry (2nd attempt), use cloud-nuke as a last resort to nuke the entire VPC.
      if [[ "$RETRY_DESTROY" == "true" ]]; then
        echo "[$cluster_id] Retry: running cloud-nuke on VPC as fallback..."
        local nuke_config="${temp_dir}/matching-vpc.yml"
        cp "$SCRIPT_DIR/matching-vpc.yml" "$nuke_config"
        local safe_id
        safe_id=$(printf '%s' "$cluster_id" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
        NAME_REGEX="^${safe_id}.*" yq eval '.VPC.include.names_regex = [strenv(NAME_REGEX)]' -i "$nuke_config"
        cloud-nuke aws --config "$nuke_config" --resource-type vpc --region "$AWS_REGION" --force
      fi
  fi

  cd "$temp_dir" || return 1

  tree "." || return 1

  echo "tf state: bucket=$BUCKET key=${cluster_folder}/${cluster_id}.tfstate region=$AWS_S3_REGION"

  if ! terraform init -backend-config="bucket=$BUCKET" -backend-config="key=${cluster_folder}/${cluster_id}.tfstate" -backend-config="region=$AWS_S3_REGION"; then return 1; fi

  # Edit the name of the cluster
  sed -i -e "s/\(rosa_cluster_name\s*=\s*\"\)[^\"]*\(\"\)/\1${cluster_id}\2/" cluster.tf

  # Retry loop: after ROSA cluster destruction (~28min), the cloud provider may leave
  # behind orphan resources (SGs, ENIs) in the VPC. If terraform fails with DependencyViolation,
  # we re-run VPC dependency cleanup and retry.
  local max_destroy_attempts=3
  local destroy_succeeded=false
  for attempt in $(seq 1 $max_destroy_attempts); do
    local output
    if output=$(terraform destroy -auto-approve 2>&1); then
      destroy_succeeded=true
      break
    fi
    echo "$output"

    # On DependencyViolation, re-clean VPC dependencies and retry
    if [[ "$output" == *"DependencyViolation"* && $attempt -lt $max_destroy_attempts ]]; then
      echo "[$cluster_id] DependencyViolation detected (attempt $attempt/$max_destroy_attempts)"
      echo "[$cluster_id] Re-running VPC dependency cleanup before retry..."

      local retry_vpc
      retry_vpc=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_id}*" \
                  --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION" 2>/dev/null)
      if [[ -n "$retry_vpc" && "$retry_vpc" != "None" ]]; then
        cleanup_vpc_dependencies "$retry_vpc" "$AWS_REGION"
      fi

      echo "[$cluster_id] Waiting 30s for async resource cleanup..."
      sleep 30
      continue
    fi

    return 1
  done

  if [[ "$destroy_succeeded" != "true" ]]; then
    echo "Error destroying cluster $cluster_id after $max_destroy_attempts attempts"
    return 1
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

for cluster_id in $clusters; do
  cd "$CURRENT_DIR" || return 1


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

    if ! destroy_cluster "$cluster_id" "$cluster_folder"; then
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

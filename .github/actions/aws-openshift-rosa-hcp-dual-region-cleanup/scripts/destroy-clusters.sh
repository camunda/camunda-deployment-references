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
# - CLUSTER_1_AWS_REGION and CLUSTER_2_AWS_REGION variables defined on the regions of the clusters

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

if [ -z "$CLUSTER_1_AWS_REGION" ]; then
  echo "Error: The environment variable CLUSTER_1_AWS_REGION is not set."
  exit 1
fi

if [ -z "$CLUSTER_2_AWS_REGION" ]; then
  echo "Error: The environment variable CLUSTER_2_AWS_REGION is not set."
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
AWS_REGION=${AWS_REGION:-$CLUSTER_1_AWS_REGION}
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
    # Parse attached ENIs once: detach and remember IDs for later deletion.
    local attached_eni_ids=()
    while IFS=$'\t' read -r eni_id attachment_id; do
      [[ -z "$eni_id" ]] && continue
      [[ -z "$attachment_id" || "$attachment_id" == "None" ]] && continue
      echo "  Detaching Network Interface: $eni_id (attachment: $attachment_id)"
      aws ec2 detach-network-interface --attachment-id "$attachment_id" --force --region "$region" 2>/dev/null || true
      attached_eni_ids+=("$eni_id")
    done <<< "$attached_enis"
    echo "  Waiting for ENIs to detach..."
    # Use a slightly longer wait to handle multiple ENIs and potential AWS throttling
    sleep 20
    for eni_id in "${attached_eni_ids[@]}"; do
      [[ -z "$eni_id" ]] && continue
      echo "  Deleting Network Interface: $eni_id"
      aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$region" 2>/dev/null || true
    done
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

  # Extract cluster name from group_id by splitting at "-oOo-" and taking the first element
  cluster_1_name=$(echo "$group_id" | awk -F"-oOo-" '{print $1}')
  cluster_2_name=$(echo "$group_id" | awk -F"-oOo-" '{print $2}')

  # Validate that both cluster names are non-empty to avoid overly broad regex patterns
  if [[ -z "$cluster_1_name" || -z "$cluster_2_name" ]]; then
    echo "Error: Failed to parse dual-region cluster names from group_id '$group_id' (expected format: name1-oOo-name2)"
    return 1
  fi

  # Pre-cleanup: remove cloud-provider-managed resources inside the VPCs before terraform destroy.
  # ROSA HCP creates AWS resources (LBs, SGs, ENIs) outside of Terraform state management.
  # When Terraform destroys the ROSA cluster, AWS/Red Hat cleanup is asynchronous, meaning the VPC
  # may still have active dependencies when Terraform tries to delete it, causing a ~20min retry loop
  # followed by failure. We proactively remove these orphan resources while keeping the VPCs intact
  # for Terraform to delete cleanly.
  if [[ "$module_name" == "clusters" ]]; then
    local vpc_1_id vpc_2_id
    vpc_1_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_1_name}*" --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION")
    vpc_2_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_2_name}*" --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_2_AWS_REGION")
    if [[ -n "$vpc_1_id" && "$vpc_1_id" != "None" ]]; then
      echo "[$group_id] Pre-cleanup: removing orphan resources in VPC $vpc_1_id (region 1)..."
      cleanup_vpc_dependencies "$vpc_1_id" "$CLUSTER_1_AWS_REGION"
    fi
    if [[ -n "$vpc_2_id" && "$vpc_2_id" != "None" ]]; then
      echo "[$group_id] Pre-cleanup: removing orphan resources in VPC $vpc_2_id (region 2)..."
      cleanup_vpc_dependencies "$vpc_2_id" "$CLUSTER_2_AWS_REGION"
    fi

    # On retry (2nd attempt), use cloud-nuke as a last resort to nuke the entire VPCs.
    if [[ "$RETRY_DESTROY" == "true" ]]; then
      echo "[$group_id] Retry: running cloud-nuke on VPCs as fallback..."
      local nuke_config_1="${temp_dir}/matching-vpc-1.yml"
      local nuke_config_2="${temp_dir}/matching-vpc-2.yml"
      cp "$SCRIPT_DIR/matching-vpc.yml" "$nuke_config_1"
      cp "$SCRIPT_DIR/matching-vpc.yml" "$nuke_config_2"
      local safe_id_1 safe_id_2
      safe_id_1=$(printf '%s' "$cluster_1_name" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
      safe_id_2=$(printf '%s' "$cluster_2_name" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
      NAME_REGEX="^${safe_id_1}.*" yq eval '.VPC.include.names_regex = [strenv(NAME_REGEX)]' -i "$nuke_config_1"
      NAME_REGEX="^${safe_id_2}.*" yq eval '.VPC.include.names_regex = [strenv(NAME_REGEX)]' -i "$nuke_config_2"
      cloud-nuke aws --config "$nuke_config_1" --resource-type vpc --region "$CLUSTER_1_AWS_REGION" --force
      cloud-nuke aws --config "$nuke_config_2" --resource-type vpc --region "$CLUSTER_2_AWS_REGION" --force
    fi
  fi

  if [[ "$module_name" == "backup_bucket" ]]; then
    hash=$(echo -n "$group_id" | sha256sum | cut -c1-8)
    export TF_VAR_bucket_name="cb-$hash"
    echo "Bucket name is set to $TF_VAR_bucket_name"
  elif  [[ "$module_name" == "clusters" ]]; then
    echo "Updating cluster names in Terraform configuration..."

    export TF_VAR_cluster_1_region="$CLUSTER_1_AWS_REGION"
    export TF_VAR_cluster_2_region="$CLUSTER_2_AWS_REGION"

    sed -i -e "s/\(rosa_cluster_1_name\s*=\s*\"\)[^\"]*\(\"\)/\1${cluster_1_name}\2/" cluster_region_1.tf
    sed -i -e "s/\(rosa_cluster_2_name\s*=\s*\"\)[^\"]*\(\"\)/\1${cluster_2_name}\2/" cluster_region_2.tf
  elif [[ "$module_name" == "peering" ]]; then
    echo "Setting values for VPC peering variables..."

    export TF_VAR_cluster_1_region="$CLUSTER_1_AWS_REGION"
    export TF_VAR_cluster_2_region="$CLUSTER_2_AWS_REGION"
    TF_VAR_cluster_1_vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_1_name}*" --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION")
    TF_VAR_cluster_2_vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_2_name}*" --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_2_AWS_REGION")

    if [[ "$TF_VAR_cluster_1_vpc_id" == "None" || -z "$TF_VAR_cluster_1_vpc_id" || \
          "$TF_VAR_cluster_2_vpc_id" == "None" || -z "$TF_VAR_cluster_2_vpc_id" ]]; then
      echo "Error: At least one of the VPCs (cluster_1: $TF_VAR_cluster_1_vpc_id, cluster_2: $TF_VAR_cluster_2_vpc_id) not found."

      echo "Assuming it was deleted by Cloud Nuke. Cleaning up Terraform state..."
      aws s3 rm "s3://$BUCKET/$module_tfstate" --recursive || return 1
      aws s3api delete-object --bucket "$BUCKET" --key "$module_tfstate" || return 1
      cd - || return 1
      rm -rf "$temp_dir" || return 1

      return 0
    fi

    export TF_VAR_cluster_1_vpc_id
    export TF_VAR_cluster_2_vpc_id
  fi


  echo "Initializing Terraform for module $module_name (tfstate: $module_tfstate)"

  if ! terraform init -backend-config="bucket=$BUCKET" -backend-config="key=$module_tfstate" -backend-config="region=$AWS_S3_REGION"; then
    echo "Error initializing Terraform for module $module_name in group $group_id"
    return 1
  fi

  echo "Destroying module $module_name in group $group_id"

  # Retry loop: after ROSA cluster destruction (~28min), the cloud provider may leave
  # behind orphan resources (SGs, ENIs) in the VPC. If terraform fails with DependencyViolation,
  # we re-run VPC dependency cleanup and retry.
  local max_destroy_attempts=3
  local destroy_succeeded=false
  for attempt in $(seq 1 $max_destroy_attempts); do
    if output_tf_destroy=$(terraform destroy -auto-approve 2>&1); then
      destroy_succeeded=true
      echo "$output_tf_destroy"
      break
    fi
    echo "$output_tf_destroy"

    if [[ "$module_name" == "clusters" && "$output_tf_destroy" == *"CLUSTERS-MGMT-404"* ]]; then
      echo "The cluster appears to have already been deleted (error: CLUSTERS-MGMT-404). Considering the deletion successful (likely due to cloud-nuke)."
      destroy_succeeded=true
      break
    fi

    # On DependencyViolation, re-clean VPC dependencies and retry
    if [[ "$output_tf_destroy" == *"DependencyViolation"* && $attempt -lt $max_destroy_attempts ]]; then
      echo "[$group_id][$module_name] DependencyViolation detected (attempt $attempt/$max_destroy_attempts)"
      echo "[$group_id][$module_name] Re-running VPC dependency cleanup before retry..."

      local retry_vpc1 retry_vpc2
      retry_vpc1=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_1_name}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION" 2>/dev/null)
      retry_vpc2=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_2_name}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_2_AWS_REGION" 2>/dev/null)
      [[ -n "$retry_vpc1" && "$retry_vpc1" != "None" ]] && cleanup_vpc_dependencies "$retry_vpc1" "$CLUSTER_1_AWS_REGION"
      [[ -n "$retry_vpc2" && "$retry_vpc2" != "None" ]] && cleanup_vpc_dependencies "$retry_vpc2" "$CLUSTER_2_AWS_REGION"

      echo "[$group_id][$module_name] Waiting 30s for async resource cleanup..."
      sleep 30
      continue
    fi

    # For non-DependencyViolation errors we fail fast instead of retrying, since these
    # typically indicate configuration or logic issues (e.g. invalid Terraform, IAM),
    # not transient AWS conditions. Only DependencyViolation (and known special cases)
    # are retried above.
    echo "Error destroying module $module_name in group $group_id"
    return 1
  done

  if [[ "$destroy_succeeded" != "true" ]]; then
    echo "Error destroying module $module_name in group $group_id after $max_destroy_attempts attempts"
    return 1
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
  groups=$(echo "$all_objects" | awk '{print $2}' | grep "tfstate-$ID_OR_ALL-1-oOo-$ID_OR_ALL-2/" | sed -n 's#^tfstate-\(.*\)/$#\1#p')

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
    module_order=("backup_bucket" "peering" "clusters")
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
    if ! file_count=$(aws s3 ls "s3://$BUCKET/$folder" --recursive | grep -cv '/$')
    then
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

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

# Remove cloud-provider-managed resources (Load Balancers, Security Groups, ENIs, etc.) inside a VPC.
# These are created outside of Terraform by ROSA operators, EKS ingress controllers, etc.
# The VPC itself is left intact for Terraform to manage.
# This is a best-effort cleanup: resources still in use will fail to delete and be silently skipped.
cleanup_vpc_dependencies() {
  local vpc_id=$1
  local region=$2

  echo "  Cleaning up VPC dependencies for $vpc_id in $region..."

  # 1. Delete Load Balancers (ELBv2: ALB/NLB — primary cause of DependencyViolation)
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

  # 3. Delete NAT Gateways (can block subnet/EIP deletion)
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

  # 7. Delete non-main Route Table associations and Route Tables
  local rtb_ids
  rtb_ids=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query "RouteTables[?Associations[?Main!=\`true\`]].RouteTableId" \
    --output text --region "$region" 2>/dev/null)
  if [[ -n "$rtb_ids" && "$rtb_ids" != "None" ]]; then
    for rtb_id in $rtb_ids; do
      # Remove non-main associations first
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

  # Pre-cleanup: remove cloud-provider-managed resources inside the VPC before terraform destroy.
  # Cloud providers (ROSA HCP, EKS via ingress controllers, etc.) create AWS resources
  # (Load Balancers, Security Groups, ENIs) outside of Terraform state.
  # When terraform destroys the cluster, the cleanup on the provider side is asynchronous
  # and may not complete before Terraform attempts to delete the VPC, causing
  # DependencyViolation errors and ~20min timeouts.
  # We proactively remove these orphan resources while keeping the VPC intact for
  # Terraform to delete cleanly.
  if [[ "$module_name" == "cluster" ]]; then
    local vpc_check
    vpc_check=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${group_id}*" \
                --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION" 2>/dev/null)
    if [[ -n "$vpc_check" && "$vpc_check" != "None" ]]; then
      echo "[$group_id][$module_name] Pre-cleanup: removing orphan resources in VPC $vpc_check..."
      cleanup_vpc_dependencies "$vpc_check" "$AWS_REGION"

      # On retry (2nd attempt), use cloud-nuke as a last resort to nuke the entire VPC.
      # This is more aggressive (deletes the VPC itself) but ensures no resources are left behind.
      if [[ "$RETRY_DESTROY" == "true" ]]; then
        echo "[$group_id][$module_name] Retry: running cloud-nuke on VPC as fallback..."
        local nuke_config="${temp_dir}/matching-vpc.yml"
        mkdir -p "$temp_dir"
        cp "$SCRIPT_DIR/matching-vpc.yml" "$nuke_config"
        local safe_id
        safe_id=$(printf '%s' "$group_id" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
        NAME_REGEX="^${safe_id}.*" yq eval '.VPC.include.names_regex = [strenv(NAME_REGEX)]' -i "$nuke_config"
        cloud-nuke aws --config "$nuke_config" --resource-type vpc --region "$AWS_REGION" --force
      fi
    fi
  fi

  # Handle dual-region (we may need a better way to abstract this)
  local tf_config_file="$SCRIPT_DIR/config"
  if [[ "$module_name" =~ ^(clusters|peering)$ ]]; then
    [[ -z "$CLUSTER_1_AWS_REGION" || -z "$CLUSTER_2_AWS_REGION" ]] && {
      echo "Error: CLUSTER_1_AWS_REGION and CLUSTER_2_AWS_REGION must be set"
      exit 1
    }

    local cluster_1_name cluster_2_name
    if [[ "$group_id" == *"-oOo-"* ]]; then
      # ROSA-style: two distinct cluster names separated by -oOo-
      cluster_1_name=$(echo "$group_id" | awk -F"-oOo-" '{print $1}')
      cluster_2_name=$(echo "$group_id" | awk -F"-oOo-" '{print $2}')
    else
      # EKS-style: single prefix used for both clusters (suffixed with region names)
      cluster_1_name="$group_id"
      cluster_2_name="$group_id"
    fi

    # Validate that both cluster names are non-empty to avoid overly broad regex patterns
    if [[ -z "$cluster_1_name" || -z "$cluster_2_name" ]]; then
      echo "Error: Failed to parse dual-region cluster names from group_id '$group_id' (expected format: name1-oOo-name2)"
      exit 1
    fi

    tf_config_file="$SCRIPT_DIR/config-dual-region"

    # Pre-cleanup for dual-region: same rationale as single-cluster above.
    if [[ "$module_name" == "clusters" ]]; then
      local vpc1_check vpc2_check
      vpc1_check=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_1_name}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION" 2>/dev/null)
      vpc2_check=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_2_name}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_2_AWS_REGION" 2>/dev/null)
      if [[ -n "$vpc1_check" && "$vpc1_check" != "None" ]]; then
        echo "[$group_id][$module_name] Pre-cleanup: removing orphan resources in VPC $vpc1_check (region 1)..."
        cleanup_vpc_dependencies "$vpc1_check" "$CLUSTER_1_AWS_REGION"
      fi
      if [[ -n "$vpc2_check" && "$vpc2_check" != "None" ]]; then
        echo "[$group_id][$module_name] Pre-cleanup: removing orphan resources in VPC $vpc2_check (region 2)..."
        cleanup_vpc_dependencies "$vpc2_check" "$CLUSTER_2_AWS_REGION"
      fi

      # On retry, use cloud-nuke as a last resort for dual-region VPCs.
      if [[ "$RETRY_DESTROY" == "true" ]]; then
        echo "[$group_id][$module_name] Retry: running cloud-nuke on dual-region VPCs as fallback..."
        local nuke_config="${temp_dir}/matching-vpc.yml"
        mkdir -p "$temp_dir"
        cp "$SCRIPT_DIR/matching-vpc.yml" "$nuke_config"
        local safe_c1 safe_c2
        safe_c1=$(printf '%s' "$cluster_1_name" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
        safe_c2=$(printf '%s' "$cluster_2_name" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
        NAME_REGEX_1="^${safe_c1}.*" NAME_REGEX_2="^${safe_c2}.*" \
          yq eval '.VPC.include.names_regex = [strenv(NAME_REGEX_1), strenv(NAME_REGEX_2)]' -i "$nuke_config"
        [[ -n "$vpc1_check" && "$vpc1_check" != "None" ]] && \
          cloud-nuke aws --config "$nuke_config" --resource-type vpc --region "$CLUSTER_1_AWS_REGION" --force
        [[ -n "$vpc2_check" && "$vpc2_check" != "None" ]] && \
          cloud-nuke aws --config "$nuke_config" --resource-type vpc --region "$CLUSTER_2_AWS_REGION" --force
      fi
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

    # For non-OpenShift (EKS) dual-region, adjust provider aliases to match the terraform config
    # EKS uses "accepter" alias instead of "cluster_2", and doesn't need "cluster_1" alias
    if [[ "${OPENSHIFT:-false}" == "false" ]]; then
      echo "[$group_id][$module_name] Adjusting provider aliases for EKS dual-region"
      sed -i 's/alias  = "cluster_2"/alias  = "accepter"/' "$temp_dir/config.tf"
      sed -i '/alias  = "cluster_1"/d' "$temp_dir/config.tf"
    fi

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

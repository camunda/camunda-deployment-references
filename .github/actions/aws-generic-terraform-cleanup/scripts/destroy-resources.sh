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

# `selftest` exercises the pure classifier defined further down and takes none
# of the runtime arguments, so it skips the validation below and is dispatched
# once the functions exist.
SELFTEST=false
# Matched on the full argv, not just $1: the real path takes four or more
# arguments, so a bucket that happens to be named "selftest" cannot trip this.
[[ $# -eq 1 && "$1" == "selftest" ]] && SELFTEST=true

# Validate ORDER argument
if [[ "$SELFTEST" != true && -z "$ORDER" ]]; then
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

# Detach an IAM policy from every entity that still holds it.
#
# Terraform destroys an aws_iam_policy it owns, but it can only detach the
# attachments it still tracks. When an earlier partial destroy dropped the IRSA
# role modules from the state while leaving the roles in AWS, the policy stays
# attached to an entity nothing tracks and DeletePolicy fails for good with
# `DeleteConflict: Cannot delete a policy attached to entities`. Retrying and
# cloud-nuke do not help — the attachment has to go first.
#
# Safe by construction: this only ever runs on a policy Terraform is deleting.
# The holding entities are printed, because they are orphans in their own right.
# Reached only through remediate_iam_attachments, which the retry loop
# dispatches by name, so shellcheck cannot see a call site for either.
# shellcheck disable=SC2329,SC2317
detach_iam_policy_entities() {
  local policy_arn=$1
  local entity_filter query kind name

  echo "  Detaching $policy_arn from every entity that still holds it..."

  # `aws --output text` prints the literal "None" for an empty result, so it
  # has to be skipped explicitly or we log "orphaned role None" and issue a
  # detach call for it.
  for entity_filter in Role User Group; do
    case "$entity_filter" in
      Role)  query='PolicyRoles[].RoleName';   kind=role  ;;
      User)  query='PolicyUsers[].UserName';   kind=user  ;;
      Group) query='PolicyGroups[].GroupName'; kind=group ;;
    esac

    while read -r name; do
      [[ -z "$name" || "$name" == "None" ]] && continue
      echo "    orphaned $kind $name -> detaching"
      aws iam "detach-${kind}-policy" "--${kind}-name" "$name" --policy-arn "$policy_arn" || true
    done < <(aws iam list-entities-for-policy --policy-arn "$policy_arn" \
               --entity-filter "$entity_filter" --query "$query" \
               --output text 2>/dev/null | tr '\t' '\n')
  done
}

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

# classify_destroy_error maps a failed `terraform destroy` to the remediation
# that can recover it, or prints nothing when the failure is fatal.
#
# One place decides. Before this, five `if [[ "$output" == *...* ]]` branches
# carried both the pattern and its remediation inline in the retry loop, and the
# comment at the bottom had to enumerate them in prose to stay accurate -- a
# reliable sign the control flow no longer said it. Adding a sixth recoverable
# error is now a case here plus a function beside the others, and never a change
# to the loop.
classify_destroy_error() {
  local output="$1" module_name="$2"

  if [[ "$module_name" =~ ^(cluster|clusters)$ && "$output" == *"CLUSTERS-MGMT-404"* ]]; then
    # Not a remediation: the cluster is already gone, which is the outcome the
    # destroy wanted. The loop treats this as success.
    echo already_gone
  elif [[ "$output" == *"DependencyViolation"* ]]; then
    echo remediate_vpc_dependencies
  elif [[ "$output" == *"clusters using OIDC config"* ]]; then
    echo remediate_orphaned_oidc
  elif [[ "$output" == *"CLUSTERS-MGMT-400"* && "$output" == *"trust policy"* ]]; then
    echo remediate_broken_trust_policy
  elif [[ "$output" == *"DeleteConflict"* && "$output" == *"policy attached to entities"* ]]; then
    echo remediate_iam_attachments
  elif [[ "$output" == *"InvalidGlobalClusterStateFault"* ||
          "$output" == *"Cannot delete the last instance of the master cluster"* ]]; then
    echo remediate_aurora_global
  elif [[ -n "$(extract_s3_bucket_names "$output")" ]]; then
    echo remediate_s3_versions
  elif [[ -n "$(extract_stale_eips "$output")" ]]; then
    echo remediate_stale_eips
  fi
}

# Only accept names from the specific failed force-destroy operation, not other
# bucket names mentioned elsewhere in the Terraform output.
# extract_stale_eips <output> — allocation ids of Elastic IPs whose release
# failed because the network interface they were associated with is gone.
extract_stale_eips() {
  grep -E 'ReleaseAddress' <<<"$1" | grep -F 'InvalidNetworkInterfaceID.NotFound' |
    grep -oE 'deleting EC2 EIP \((eipalloc-[0-9a-f]+)\)' |
    sed -E 's/.*\((eipalloc-[0-9a-f]+)\)/\1/' | sort -u
}

# remediate_stale_eips releases Elastic IPs that AWS still considers associated
# with an interface that no longer exists.
#
# The cloud-nuke retry deletes a VPC's NAT gateways, and with them the ENIs the
# NAT EIPs are attached to. terraform destroy of that VPC then fails to release
# the EIPs with InvalidNetworkInterfaceID.NotFound, and stops there. The VPC
# module destroys the internet gateway after the EIPs, so the IGW stays
# attached, cloud-nuke's own DeleteVpc fails with DependencyViolation, and the
# VPC leaks (camunda/camunda-deployment-references#3595, 2026-10-18).
#
# Safe by construction: it only touches the allocation ids named in this
# module's own destroy error — EIPs Terraform was deleting anyway. Releasing
# them here is enough; the provider treats the NotFound on its next attempt as
# already deleted, and the destroy continues to the IGW and the VPC.
#
# The error does not name the region, so the caller's declared regions are
# searched, falling back to the regions the dual-region path uses.
#
# Invoked indirectly, by name, from the retry loop's dispatch -- shellcheck
# cannot see that call site.
# shellcheck disable=SC2329,SC2317
remediate_stale_eips() {
  local group_id="$1" module_name="$2" output="$3"
  local regions="${CLEANUP_REGIONS:-${AWS_REGION:-} ${CLUSTER_0_AWS_REGION:-} ${CLUSTER_1_AWS_REGION:-}}"
  local alloc region association

  for alloc in $(extract_stale_eips "$output"); do
    for region in $regions; do
      # An allocation id that is not in this region is an error, not an empty
      # answer, so a failure here just means "look in the next region".
      association=$(aws ec2 describe-addresses --region "$region" --allocation-ids "$alloc" \
        --query 'Addresses[0].AssociationId' --output text 2>/dev/null) || continue
      echo "[$group_id][$module_name] Releasing $alloc in $region, left associated with a deleted interface"
      if [[ -n "$association" && "$association" != "None" ]]; then
        aws ec2 disassociate-address --region "$region" --association-id "$association" >/dev/null 2>&1 || true
      fi
      aws ec2 release-address --region "$region" --allocation-id "$alloc" >/dev/null 2>&1 ||
        echo "[$group_id][$module_name] Could not release $alloc in $region yet; the retry will report it."
      break
    done
  done
}

extract_s3_bucket_names() {
  local bucket
  while IFS= read -r bucket; do
    [[ "$bucket" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || continue
    [[ "$bucket" == *..* || "$bucket" == *.-* || "$bucket" == *-.* ]] && continue
    [[ "$bucket" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
    printf '%s\n' "$bucket"
  done < <(awk 'BEGIN { RS="Error:" }
    /ListObjectVersions/ && /bufio.Scanner: token too long/ {
      if (match($0, /emptying S3 Bucket \([^)]*\)/)) {
        name=substr($0, RSTART, RLENGTH)
        sub(/^emptying S3 Bucket \(/, "", name); sub(/\)$/, "", name)
        print name
      }
    }' <<< "$1") | sort -u
}

# Bypass the provider HTTP logger's Scanner limit. Drain one bounded page at a
# time, then list from the beginning again: deleting versions invalidates the
# need for continuation markers and keeps each delete request below 1000 items.
# shellcheck disable=SC2329,SC2317
remediate_s3_versions() {
  local group_id="$1" module_name="$2" output="$3"
  local buckets bucket region page payload result iteration
  buckets=$(extract_s3_bucket_names "$output")
  [[ -n "$buckets" ]] || return 1
  while IFS= read -r bucket; do
    region=$(aws s3api get-bucket-location --bucket "$bucket" \
      --query LocationConstraint --output text --no-cli-pager) || return 1
    case "$region" in
      None|null) region=us-east-1 ;;
      EU) region=eu-west-1 ;;
    esac
    echo "[$group_id][$module_name] Emptying versioned bucket $bucket in $region before retry..."
    for ((iteration=0; iteration<1000; iteration++)); do
      page=$(aws s3api list-object-versions --bucket "$bucket" --region "$region" \
        --max-keys 500 --no-paginate --output json --no-cli-pager) || return 1
      payload=$(jq -ce '{Objects: [(.Versions[]?, .DeleteMarkers[]?) | {Key, VersionId}], Quiet: true}
        | select((.Objects | length) <= 500)' <<< "$page") || return 1
      if [[ "$(jq '.Objects | length' <<< "$payload")" -eq 0 ]]; then
        [[ "$(jq -r '.IsTruncated // false' <<< "$page")" == false ]] || return 1
        break
      fi
      result=$(aws s3api delete-objects --bucket "$bucket" --region "$region" \
        --delete file:///dev/stdin --output json --no-cli-pager <<< "$payload") || return 1
      # DeleteObjects can return HTTP 200 with per-object failures. With
      # Quiet:true a full success prints nothing, so only check a non-empty body.
      if [[ -n "$result" ]] && ! jq -e '(.Errors // []) | length == 0' <<< "$result" >/dev/null; then
        echo "[$group_id][$module_name] S3 deletion failed: $result" >&2
        return 1
      fi
    done
    if [[ "$iteration" -eq 1000 ]]; then
      echo "[$group_id][$module_name] S3 cleanup page limit reached for $bucket" >&2
      return 1
    fi
  done <<< "$buckets"
}

# The remediations below share one signature -- group_id, module_name, output --
# so the loop can dispatch to them by name. Each is best-effort: it improves the
# odds of the next destroy, and the loop decides what to do if it does not.

# The cloud provider leaves orphan SGs and ENIs behind after a cluster teardown,
# which hold the VPC. Re-run the dependency sweep and give AWS time to catch up.
# Invoked indirectly, by name, from the retry loop's dispatch -- shellcheck
# cannot see that call site.
# shellcheck disable=SC2329,SC2317
remediate_vpc_dependencies() {
  local group_id="$1" module_name="$2"

  echo "[$group_id][$module_name] Re-running VPC dependency cleanup before retry..."

  # A caller that declared the regions to sweep has told us everything we need,
  # whatever its modules are named. Checking that first means an architecture
  # does not have to call its module "clusters" to get its VPCs unblocked --
  # the ECS dual-region states are named after their layers (app/terraform,
  # infra/terraform, vpc/terraform), and used to fall through to no sweep at
  # all. Existing `clusters` callers that set cleanup-regions already took this
  # exact path.
  if [[ -n "${CLEANUP_REGIONS:-}" ]]; then
    local region retry_vpc
    for region in $CLEANUP_REGIONS; do
      retry_vpc=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${group_id},${group_id}-*" \
                  --query "Vpcs[0].VpcId" --output text --region "$region" 2>/dev/null)
      [[ -n "$retry_vpc" && "$retry_vpc" != "None" ]] && cleanup_vpc_dependencies "$retry_vpc" "$region"
    done
  elif [[ "$module_name" == "cluster" ]]; then
    local retry_vpc
    retry_vpc=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${group_id}*" \
                --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION" 2>/dev/null)
    if [[ -n "$retry_vpc" && "$retry_vpc" != "None" ]]; then
      cleanup_vpc_dependencies "$retry_vpc" "$AWS_REGION"
    fi
  elif [[ "$module_name" == "clusters" ]]; then
    if [[ -z "$CLUSTER_0_AWS_REGION" || -z "$CLUSTER_1_AWS_REGION" ]]; then
      echo "[$group_id][$module_name] Warning: CLUSTER_0_AWS_REGION or CLUSTER_1_AWS_REGION not set, skipping VPC cleanup retry"
    else
      local retry_vpc1 retry_vpc2 retry_c1 retry_c2
      if [[ "$group_id" == *"-oOo-"* ]]; then
        retry_c1=$(echo "$group_id" | awk -F"-oOo-" '{print $1}')
        retry_c2=$(echo "$group_id" | awk -F"-oOo-" '{print $2}')
      else
        retry_c1="$group_id"
        retry_c2="$group_id"
      fi
      retry_vpc1=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${retry_c1}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_0_AWS_REGION" 2>/dev/null)
      retry_vpc2=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${retry_c2}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION" 2>/dev/null)
      [[ -n "$retry_vpc1" && "$retry_vpc1" != "None" ]] && cleanup_vpc_dependencies "$retry_vpc1" "$CLUSTER_0_AWS_REGION"
      [[ -n "$retry_vpc2" && "$retry_vpc2" != "None" ]] && cleanup_vpc_dependencies "$retry_vpc2" "$CLUSTER_1_AWS_REGION"
    fi
  fi

  echo "[$group_id][$module_name] Waiting 30s for async resource cleanup..."
  sleep 30
}

# The ROSA cluster was dropped from the state by an earlier partial destroy but
# still exists in RHCS, and the OIDC config cannot go while it is referenced.
# Drop the config from state so the rest of the group can be destroyed;
# cleanup-ghost-rosa-clusters.sh picks up the orphan.
# Invoked indirectly, by name, from the retry loop's dispatch -- shellcheck
# cannot see that call site.
# shellcheck disable=SC2329,SC2317
remediate_orphaned_oidc() {
  local group_id="$1" module_name="$2" resource

  echo "[$group_id][$module_name] Removing OIDC config resources from Terraform state to unblock destroy..."
  terraform state list 2>/dev/null | grep "oidc_config" | while read -r resource; do
    echo "[$group_id][$module_name] Removing from state: $resource"
    terraform state rm "$resource" 2>/dev/null || true
  done
}

# The account IAM roles exist but their trust policies no longer let Red Hat's
# service assume the Installer role, so RHCS cannot delete the cluster.
# Invoked indirectly, by name, from the retry loop's dispatch -- shellcheck
# cannot see that call site.
# shellcheck disable=SC2329,SC2317
remediate_broken_trust_policy() {
  local group_id="$1" module_name="$2"

  echo "[$group_id][$module_name] Recreating account roles to restore trust policies..."
  rosa login --token="$RHCS_TOKEN"
  rosa create account-roles --mode auto --yes --hosted-cp --prefix "${group_id}-account" || true
}

# An IAM policy Terraform owns is still attached to an entity Terraform no
# longer tracks, so DeletePolicy fails identically on every run and the whole
# group leaks, state file included.
# Invoked indirectly, by name, from the retry loop's dispatch -- shellcheck
# cannot see that call site.
# shellcheck disable=SC2329,SC2317
remediate_iam_attachments() {
  local group_id="$1" module_name="$2" output="$3" stuck_policy

  echo "[$group_id][$module_name] Detaching IAM policies still attached to untracked entities..."
  while read -r stuck_policy; do
    [[ -z "$stuck_policy" ]] && continue
    detach_iam_policy_entities "$stuck_policy"
  done < <(grep -oE 'arn:aws:iam::[0-9]+:policy/[A-Za-z0-9+=,.@_/-]+' <<<"$output" | sort -u)
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

  # Handle dual-region (we may need a better way to abstract this)
  local tf_config_file="$SCRIPT_DIR/config"
  if [[ "$module_name" =~ ^(clusters|peering)$ ]]; then
    [[ -z "${TF_CONFIG_PATH:-}" && (-z "$CLUSTER_0_AWS_REGION" || -z "$CLUSTER_1_AWS_REGION") ]] && {
      echo "Error: CLUSTER_0_AWS_REGION and CLUSTER_1_AWS_REGION must be set"
      exit 1
    }

    local cluster_0_name cluster_1_name
    if [[ "$group_id" == *"-oOo-"* ]]; then
      # ROSA-style: two distinct cluster names separated by -oOo-
      cluster_0_name=$(echo "$group_id" | awk -F"-oOo-" '{print $1}')
      cluster_1_name=$(echo "$group_id" | awk -F"-oOo-" '{print $2}')
    else
      # EKS-style: single prefix used for both clusters (suffixed with region names)
      cluster_0_name="$group_id"
      cluster_1_name="$group_id"
    fi

    # Validate that both cluster names are non-empty to avoid overly broad regex patterns
    if [[ -z "$cluster_0_name" || -z "$cluster_1_name" ]]; then
      echo "Error: Failed to parse dual-region cluster names from group_id '$group_id' (expected format: name1-oOo-name2)"
      exit 1
    fi

    tf_config_file="$SCRIPT_DIR/config-dual-region"

    if [[ "$module_name" == "clusters" && -z "${CLEANUP_REGIONS:-}" ]]; then
      local vpc1_check vpc2_check
      vpc1_check=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_0_name}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_0_AWS_REGION" 2>/dev/null)
      vpc2_check=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_1_name}*" \
                   --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION" 2>/dev/null)
      if [[ -n "$vpc1_check" && "$vpc1_check" != "None" ]]; then
        echo "[$group_id][$module_name] Pre-cleanup: removing orphan resources in VPC $vpc1_check (region 0)..."
        cleanup_vpc_dependencies "$vpc1_check" "$CLUSTER_0_AWS_REGION"
      fi
      if [[ -n "$vpc2_check" && "$vpc2_check" != "None" ]]; then
        echo "[$group_id][$module_name] Pre-cleanup: removing orphan resources in VPC $vpc2_check (region 1)..."
        cleanup_vpc_dependencies "$vpc2_check" "$CLUSTER_1_AWS_REGION"
      fi

      # On retry, use cloud-nuke as a last resort for dual-region VPCs.
      if [[ "$RETRY_DESTROY" == "true" ]]; then
        echo "[$group_id][$module_name] Retry: running cloud-nuke on dual-region VPCs as fallback..."
        local nuke_config="${temp_dir}/matching-vpc.yml"
        mkdir -p "$temp_dir"
        cp "$SCRIPT_DIR/matching-vpc.yml" "$nuke_config"
        local safe_c1 safe_c2
        safe_c1=$(printf '%s' "$cluster_0_name" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
        safe_c2=$(printf '%s' "$cluster_1_name" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
        NAME_REGEX_1="^${safe_c1}.*" NAME_REGEX_2="^${safe_c2}.*" \
          yq eval '.VPC.include.names_regex = [strenv(NAME_REGEX_1), strenv(NAME_REGEX_2)]' -i "$nuke_config"
        [[ -n "$vpc1_check" && "$vpc1_check" != "None" ]] && \
          cloud-nuke aws --config "$nuke_config" --resource-type vpc --region "$CLUSTER_0_AWS_REGION" --force
        [[ -n "$vpc2_check" && "$vpc2_check" != "None" ]] && \
          cloud-nuke aws --config "$nuke_config" --resource-type vpc --region "$CLUSTER_1_AWS_REGION" --force
      fi
    fi

    # Peering module check: we verify if both VPCs exist because the peering module contains data blocks
    # that will fail if either VPC is not found. In this case, we directly clean up the state.
    if [[ "$module_name" == "peering" ]]; then
      local vpc1 vpc2
      vpc1=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_0_name}*" \
             --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_0_AWS_REGION")
      vpc2=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${cluster_1_name}*" \
             --query "Vpcs[0].VpcId" --output text --region "$CLUSTER_1_AWS_REGION")

      if [[ "$vpc1" == "None" || -z "$vpc1" || "$vpc2" == "None" || -z "$vpc2" ]]; then
        echo "Error: Missing VPCs ($vpc1 / $vpc2), assuming nuked."
        cleanup_state
        return 0
      fi
    fi
  fi

  # An explicit provider configuration wins over the heuristics above. The module
  # name alone cannot tell a two-region state from an N-region one -- both call
  # their module `clusters` -- and picking the wrong provider set makes the
  # destroy fail with "Provider configuration not present", leaving a whole
  # regional deployment behind.
  if [[ -n "${TF_CONFIG_PATH:-}" ]]; then
    # Resolved inside the checkout so an architecture can own its own file, and
    # confined to it so the value cannot hand the destroy run an arbitrary file
    # from the runner as its provider config.
    local repo_root resolved
    repo_root="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
    # Plain realpath (no GNU -m) so the guard also runs on macOS; a missing
    # file resolves to nothing and is reported as not found.
    if ! resolved="$(cd "$repo_root" && realpath -- "$TF_CONFIG_PATH" 2>/dev/null)" || [[ ! -f "$resolved" ]]; then
      echo "Error: tf-config-path '$TF_CONFIG_PATH' not found"
      exit 1
    fi
    if [[ "$resolved" != "$repo_root/"* ]]; then
      echo "Error: tf-config-path '$TF_CONFIG_PATH' resolves outside the repository"
      exit 1
    fi
    echo "[$group_id][$module_name] Using the provider configuration $TF_CONFIG_PATH"
    tf_config_file="$resolved"
  fi

  # Last-resort VPC sweep before a retry pass, for any architecture that
  # declared its regions. No-op on the first pass.
  nuke_vpcs_in_cleanup_regions "$group_id" "$module_name" "$temp_dir"

  mkdir -p "$temp_dir"
  cp "$tf_config_file" "$temp_dir/config.tf" || return 1
  # The temp dir sits outside the checkout, so an asdf-managed terraform would
  # find no version there; carry the repository's pins along.
  cp "$SCRIPT_DIR/../../../../.tool-versions" "$temp_dir/" 2>/dev/null || true
  cd "$temp_dir" || return 1

  echo "[$group_id][$module_name] Initializing Terraform"
  if [[ "$tf_config_file" == *"config-dual-region" ]]; then

    # For non-OpenShift (EKS) dual-region, adjust provider aliases to match the terraform config
    # EKS uses "accepter" alias instead of "cluster_1", and doesn't need "cluster_0" alias
    if [[ "${OPENSHIFT:-false}" == "false" ]]; then
      echo "[$group_id][$module_name] Adjusting provider aliases for EKS dual-region"
      # Not sed -i: GNU and BSD sed disagree on its argument.
      sed -e 's/alias  = "cluster_1"/alias  = "accepter"/' -e '/alias  = "cluster_0"/d' \
        "$temp_dir/config.tf" > "$temp_dir/config.tf.new" && mv "$temp_dir/config.tf.new" "$temp_dir/config.tf" || return 1
    fi

    cat > "$temp_dir/terraform.tfvars" <<EOF
cluster_0_region = "$CLUSTER_0_AWS_REGION"
cluster_1_region = "$CLUSTER_1_AWS_REGION"
EOF

    terraform init \
      -backend-config="bucket=$BUCKET" \
      -backend-config="key=$key" \
      -backend-config="region=$AWS_S3_REGION" || return 1
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

  # Retry loop: after ROSA/EKS cluster destruction (~28min), the cloud provider
  # may leave behind orphan resources (SGs, ENIs) in the VPC, and RHCS may be
  # mid-way through its own teardown. Which of those is recoverable, and how, is
  # decided by classify_destroy_error and the remediate_* functions above; this
  # loop only orchestrates.
  local max_destroy_attempts=3
  local destroy_succeeded=false
  local handler
  for attempt in $(seq 1 $max_destroy_attempts); do
    # Stream to the group log as well: a pass killed by its budget never
    # returns, and only the streamed copy then shows the resource it hung on.
    # Groups run in parallel, so tag each streamed line with its group and
    # module. $output stays untagged for classify_destroy_error.
    if output=$(terraform destroy -auto-approve -no-color 2>&1 |
      tee >(tag_stream "$group_id" "$module_name" >&2)); then
      destroy_succeeded=true
      break
    fi

    # terraform prints a full red `Error: deleting EC2 VPC (...):
    # DependencyViolation` block for a condition the dispatch below routinely
    # recovers from on the next attempt — that block is why this lane reads as
    # permanently broken in #3122, when every destroy was in fact completing on
    # attempt 2. The detail is above now; say plainly whether anything is going
    # to be done about it, tagged so a recovered attempt cannot be mistaken for
    # the job's cause of death.
    if [[ $attempt -lt $max_destroy_attempts ]]; then
      echo "[$group_id][$module_name] destroy attempt ${attempt}/${max_destroy_attempts} failed; a retry may still recover it."
    else
      echo "[$group_id][$module_name] destroy attempt ${attempt}/${max_destroy_attempts} failed; no attempts left."
    fi

    handler=$(classify_destroy_error "$output" "$module_name")

    if [[ "$handler" == "already_gone" ]]; then
      echo "[$group_id][$module_name] Cluster already deleted (CLUSTERS-MGMT-404). Considering successful."
      destroy_succeeded=true
      break
    fi

    # No handler means the failure is not one we know how to recover from --
    # typically a configuration or logic problem rather than a transient AWS or
    # RHCS condition -- so fail fast rather than burning two more destroys on it.
    # A handler on the last attempt has nothing left to retry into.
    if [[ -z "$handler" ]]; then
      echo "Error destroying $module_name in $group_id"
      return 1
    fi
    if [[ $attempt -ge $max_destroy_attempts ]]; then
      echo "[$group_id][$module_name] ${handler#remediate_} still failing on the last attempt"
      echo "Error destroying $module_name in $group_id"
      return 1
    fi

    echo "[$group_id][$module_name] recoverable failure, running ${handler} (attempt $attempt/$max_destroy_attempts)"
    "$handler" "$group_id" "$module_name" "$output"
  done

  if [[ "$destroy_succeeded" != "true" ]]; then
    echo "Error destroying $module_name in $group_id after $max_destroy_attempts attempts"
    return 1
  fi

  echo "[$group_id][$module_name] Cleaning up"
  cleanup_state
}


# cloud-nuke is the last resort when a Terraform destroy has already failed
# once and something in the VPC is still holding it. It is a second-pass
# fallback only: the first destroy must retain ownership of its VPC resources
# and delete them in dependency order, and removing tracked subnets or ENIs up
# front corrupts that plan.
#
# Driven by CLEANUP_REGIONS rather than by the module name. It used to sit
# inside the branch that also picks the dual-region provider config, which
# meant only a module literally named "clusters" could ever reach it — an
# architecture whose states are named after their layers got no fallback at
# all, however many regions it spanned.
#
# Only runs for the LAST module in the destruction order. That order is the
# reverse of the dependency order, so the last state is the one that owns the
# VPC, and everything that lived inside it has already been destroyed. Nuking
# earlier would delete subnets and ENIs that the states still queued behind it
# have in their own plans — exactly the corruption this function's own warning
# describes. Previously the `clusters` gate achieved this by accident, because
# `clusters` was last for every architecture that reached here; an order like
# `app/terraform,infra/terraform,vpc/terraform` does not have that property.
# select_target_groups <target> — reads S3 keys on stdin, prints the group ids
# the target selects.
#
# Select groups whose id is the target, or ends in `-<target>`. Callers pass
# two forms: a cluster name (`ecsdr-3595`) and a run suffix (`run<id>/`),
# which the Terratest suites append to their cluster names.
#
# Bounded on both sides on purpose. A bare `grep "$ID_OR_ALL"` also matched
# every longer id with the same prefix, so `ecsdr-123` selected `ecsdr-1234`
# — and callers pass `max-age-hours: 0`, so one pull request's teardown could
# destroy another's live cluster. Matching only the exact id fixed that but
# broke the run-suffix callers: `run<id>/` then matched nothing, and with
# `fail-on-not-found: false` their per-run cleanup reported success while
# leaving the stacks behind.
select_target_groups() {
  local safe_target
  # shellcheck disable=SC2016  # the character class is a regex, not an expansion
  safe_target=$(printf '%s' "${1%/}" | sed 's/[][\.*^$(){}?+|/]/\\&/g')
  grep -E "(^|/)tfstate-([^/]*-)?${safe_target}/" |
    sed -E -n 's#(^|.*/)tfstate-([^/]*)/.*#\2#p' | sort -u
}

# module_state_exists <group_id> <module> — whether the group still has a state
# for <module>. The same test the destruction loop uses to decide what to run.
module_state_exists() {
  aws s3 ls "s3://$BUCKET/${KEY_PREFIX}tfstate-$1/$2.tfstate" >/dev/null 2>&1
}

nuke_vpcs_in_cleanup_regions() {
  local group_id="$1" module_name="$2" temp_dir="$3"

  [[ "$RETRY_DESTROY" == "true" && -n "${CLEANUP_REGIONS:-}" ]] || return 0

  # The VPC owner is the last module this group actually has, not the last one
  # declared. A greenfield ECS group has no fixture/terraform state, so gating
  # on the declared order meant the module that holds the VPC was never the
  # "last" one and the fallback never ran for it. A later module that still
  # has a state still holds resources inside the VPC, so it must go first.
  local m seen=false
  for m in "${ORDERED_MODULES[@]}"; do
    if [[ "$seen" == true ]] && module_state_exists "$group_id" "$m"; then
      echo "[$group_id][$module_name] Skipping the cloud-nuke fallback: '$m' still has a state and is destroyed after this one."
      return 0
    fi
    [[ "$m" == "$module_name" ]] && seen=true
  done

  echo "[$group_id][$module_name] Retry: running cloud-nuke on the declared regions as fallback..."

  local region vpc_check safe_id
  local nuke_config="${temp_dir}/matching-vpc.yml"
  mkdir -p "$temp_dir"
  cp "$SCRIPT_DIR/matching-vpc.yml" "$nuke_config"

  # cloud-nuke deletes whatever its config matches, so the regex is anchored to
  # this group and every regex metacharacter in the id is escaped.
  safe_id=$(printf '%s' "$group_id" | sed 's/[.[\]*+?^${}()|\\]/\\&/g')
  # Require an ownership boundary after the id. `^<id>.*` alone also matched
  # every longer id sharing the prefix, so nuking for `ecsdr-123` would have
  # taken `ecsdr-1234`'s VPCs with it. `(-|$)` keeps both the exact name and
  # the `<id>-<suffix>` forms every architecture here uses.
  NAME_REGEX="^${safe_id}(-|$)" yq eval '.VPC.include.names_regex = [strenv(NAME_REGEX)] | .EKSCluster.include.names_regex = [strenv(NAME_REGEX)]' -i "$nuke_config"

  for region in $CLEANUP_REGIONS; do
    # Same boundary as the regex above: `${group_id}*` alone matches longer ids.
    vpc_check=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${group_id},${group_id}-*" \
                --query "Vpcs[0].VpcId" --output text --region "$region" 2>/dev/null)
    if [[ -n "$vpc_check" && "$vpc_check" != "None" ]]; then
      # EKS first, VPC second. A run that dies mid-apply leaves clusters whose
      # node groups never reached the state: terraform destroy then fails with
      # "Cluster has nodegroups attached" while the cluster's ENIs keep the VPC
      # alive, so nuking VPCs alone loops on that pair.
      cloud-nuke aws --config "$nuke_config" --resource-type eks-cluster --region "$region" --force
      cloud-nuke aws --config "$nuke_config" --resource-type vpc --region "$region" --force
    fi
  done
}

# An Aurora Global cluster cannot be deleted while it still has members.
# `force_destroy` on aws_rds_global_cluster is the real fix and every
# architecture here sets it, but a member promoted out of band -- AWS during a
# region loss, or an operator mid-teardown -- can still leave the global
# cluster in a state the provider will not delete from. Detach what is left so
# the next attempt has nothing holding it.
#
# Deliberately does not delete the DB clusters: they are in the Terraform
# state, and the retry destroys them. Removing them here would strand the
# state instead.
#
# Invoked indirectly, by name, from the retry loop's dispatch -- shellcheck
# cannot see that call site.
# shellcheck disable=SC2329,SC2317
remediate_aurora_global() {
  local group_id="$1" module_name="$2" output="$3"

  echo "[$group_id][$module_name] Detaching Aurora Global cluster members before retry..."

  # The identifier is in the error text; there is no other handle on it here,
  # because the state that named it is the one failing to destroy. Terraform
  # prints the resource name in parentheses -- "deleting RDS Global Cluster
  # (my-global-db)" -- which is name-agnostic, unlike matching a naming
  # convention such as a "-global-db" suffix.
  local global_ids
  global_ids=$(grep -oE 'RDS Global Cluster \(([^)]+)\)' <<<"$output" |
    sed -E 's/.*\((.*)\)/\1/' | sort -u)

  # After a failover the writer can sit in the second region; deleting its last
  # instance then fails while a replica is attached, and the error names only
  # the instance. Find the global cluster that owns it through the members'
  # own regions, since the instance need not live in AWS_REGION.
  if [[ -z "$global_ids" ]]; then
    local instance_ids gid member region cluster_id
    instance_ids=$(grep -oE 'RDS Cluster Instance \(([^)]+)\)' <<<"$output" |
      sed -E 's/.*\((.*)\)/\1/' | sort -u)
    for gid in $(aws rds describe-global-clusters --query 'GlobalClusters[].GlobalClusterIdentifier' --output text 2>/dev/null); do
      for member in $(aws rds describe-global-clusters --global-cluster-identifier "$gid" \
        --query 'GlobalClusters[0].GlobalClusterMembers[].DBClusterArn' --output text 2>/dev/null); do
        region=$(cut -d: -f4 <<<"$member")
        cluster_id=$(cut -d: -f7 <<<"$member")
        if aws rds describe-db-clusters --region "$region" --db-cluster-identifier "$cluster_id" \
          --query 'DBClusters[0].DBClusterMembers[].DBInstanceIdentifier' --output text 2>/dev/null |
          tr '\t' '\n' | grep -qxF -f <(printf '%s\n' "$instance_ids"); then
          global_ids="$global_ids $gid"
        fi
      done
    done
    global_ids=$(tr ' ' '\n' <<<"$global_ids" | sed '/^$/d' | sort -u)
  fi

  if [[ -z "$global_ids" ]]; then
    echo "[$group_id][$module_name] No global cluster identifier in the error text; nothing to detach."
    return 0
  fi

  local global_id members arn
  for global_id in $global_ids; do
    members=$(aws rds describe-global-clusters \
      --global-cluster-identifier "$global_id" \
      --query 'GlobalClusters[0].GlobalClusterMembers[].DBClusterArn' \
      --output text 2>/dev/null) || continue

    for arn in $members; do
      echo "[$group_id][$module_name] Detaching $arn from $global_id"
      # The call has to go to the member's own region, which after a failover
      # is often not AWS_REGION.
      aws rds remove-from-global-cluster --region "$(cut -d: -f4 <<<"$arn")" \
        --global-cluster-identifier "$global_id" \
        --db-cluster-identifier "$arn" --no-cli-pager >/dev/null 2>&1 || true
    done
  done

  # Detaching is asynchronous; the next destroy attempt starts immediately
  # otherwise and sees the same state.
  sleep 30
}

# tag_stream prefixes each line with its group and module. Module names hold a
# `/` (app/terraform), so `/` cannot be the sed delimiter.
tag_stream() {
  sed -u "s#^#[$1][$2] | #"
}

# destroy_selftest checks classify_destroy_error against the verbatim error text
# each case was written for, and that every handler it can name exists.
#
# The classifier is a lookup table matched against vendor error strings, which
# is exactly the kind of thing that rots silently: a pattern typo, or a handler
# renamed without its case, would simply stop recovering and the daily cleanup
# would go back to leaking with no signal.
destroy_selftest() {
  local failures=0 got

  _expect() {
    if [[ "$2" == "$3" ]]; then
      echo "ok   $1"
    else
      echo "FAIL $1: got '$2' want '$3'"
      failures=$((failures + 1))
    fi
  }

  # Verbatim from the runs each case was written for.
  local dep_violation="Error: deleting EC2 VPC (vpc-EXAMPLE): operation error EC2: DeleteVpc, api error DependencyViolation: The vpc has dependencies and cannot be deleted."
  local oidc_in_use="Error: there are clusters using OIDC config 'EXAMPLEOIDCCONFIGID', can't delete the OIDC config"
  local trust_policy="status is 400, code is 'CLUSTERS-MGMT-400' ... Failed to delete cluster: Please make sure IAM role 'arn:aws:iam::000000000000:role/EXAMPLE-account-HCP-ROSA-Installer-Role' exists, and add it to the trust policy"
  local gone="Error: status is 404, identifier is '404', code is 'CLUSTERS-MGMT-404'"
  local delete_conflict="Error: deleting IAM Policy (arn:aws:iam::000000000000:policy/EXAMPLE-external-dns-policy): DeleteConflict: Cannot delete a policy attached to entities."
  local s3_scanner="Error: emptying S3 Bucket (eks-dual-36687d47d-7ce10-elastic-backup): listing S3 bucket (...) object versions: operation error S3: ListObjectVersions, https response error StatusCode: 200, RequestID: 8YBJSRFA8EBDPG48, ... decomposing response: bufio.Scanner: token too long"
  local unknown="Error: Invalid provider configuration"
  local last_master="Error: deleting RDS Cluster Instance (ecsdr-1234-r1-camunda-db-0): operation error RDS: DeleteDBInstance, https response error StatusCode: 400, api error InvalidDBClusterStateFault: Cannot delete the last instance of the master cluster. Delete the replica cluster before deleting the last master cluster instance."
  # Verbatim from the 2026-10-18 lifecycle-lane teardown.
  local stale_eip="Error: deleting EC2 EIP (eipalloc-05ae99ac0dafa1cf0): operation error EC2: ReleaseAddress, https response error StatusCode: 400, RequestID: 83d85ba5-6003-4c96-95c1-0385e79bf643, api error InvalidNetworkInterfaceID.NotFound: The networkInterface ID 'eni-060ceab86cbd3dd50' does not exist"
  local global_state="Error: deleting RDS Global Cluster (ecsdr-1234-global-db): operation error RDS: DeleteGlobalCluster, https response error StatusCode: 400, api error InvalidGlobalClusterStateFault: Global Cluster ecsdr-1234-global-db is not empty"

  _expect "S3 version listing scanner failure -> empty bucket" \
    "$(classify_destroy_error "$s3_scanner" clusters)" "remediate_s3_versions"
  _expect "S3 bucket name extracted from destroy error" \
    "$(extract_s3_bucket_names "$s3_scanner")" "eks-dual-36687d47d-7ce10-elastic-backup"
  _expect "unrelated scanner failure has no handler" \
    "$(classify_destroy_error 'Error: reading IAM Policy: bufio.Scanner: token too long' clusters)" ""
  local invalid_bucket
  for invalid_bucket in 'bad;command' 'bad/name' 'UPPERCASE' '-bad' 'bad-' 'a..b' 'ab' '192.168.0.1'; do
    _expect "reject invalid bucket $invalid_bucket" \
      "$(extract_s3_bucket_names "${s3_scanner/eks-dual-36687d47d-7ce10-elastic-backup/$invalid_bucket}")" ""
  done
  _expect "unrelated bucket error is not extracted" \
    "$(extract_s3_bucket_names 'Error: emptying S3 Bucket (unrelated-bucket): AccessDenied')" ""
  _expect "multiple failed buckets are deduplicated" \
    "$(extract_s3_bucket_names "$s3_scanner"$'\n\n'"$s3_scanner")" "eks-dual-36687d47d-7ce10-elastic-backup"
  _expect "another error block cannot supply the scanner failure" \
    "$(extract_s3_bucket_names 'Error: emptying S3 Bucket (unrelated-bucket): AccessDenied
Error: ListObjectVersions: bufio.Scanner: token too long')" ""

  # The subshell's aws function intercepts every call; no cloud access is possible.
  if (
    test_dir=$(mktemp -d "${TMPDIR:-.}/s3-selftest.XXXXXX") || exit 1
    trap 'rm -rf "$test_dir"' EXIT
    printf '0\n' > "$test_dir/page"
    mode=success
    aws() {
      local operation="$2" request count
      shift 2
      printf '%s\n' "$operation" >> "$test_dir/calls"
      [[ "$*" == *'--bucket eks-dual-36687d47d-7ce10-elastic-backup'* ]] || return 1
      case "$operation" in
        get-bucket-location) echo eu-west-2 ;;
        list-object-versions)
          [[ "$*" == *'--region eu-west-2 --max-keys 500 --no-paginate'* ]] || return 1
          [[ "$mode" != list_failure ]] || return 1
          count=$(< "$test_dir/page")
          printf '%s\n' "$((count + 1))" > "$test_dir/page"
          case "$count" in
            0) jq -nc '{IsTruncated:true, Versions:[range(0;499) | {Key:("snapshot/\"\\\n" + tostring), VersionId:"v1"}],
                 DeleteMarkers:[{Key:"snapshot/deleted", VersionId:"marker1"}]}' ;;
            1) echo '{"Versions":[{"Key":"snapshot/null","VersionId":"null"}]}' ;;
            *) echo '{"IsTruncated":false}' ;;
          esac ;;
        delete-objects)
          [[ "$*" == *'--region eu-west-2'* ]] || return 1
          while [[ $# -gt 0 ]]; do
            if [[ "$1" == --delete && "$2" == file:///dev/stdin ]]; then
              request=$(</dev/stdin)
              break
            fi
            shift
          done
          jq -e '.Quiet == true and (.Objects | length > 0 and length <= 500)
            and all(.Objects[]; (.Key | type == "string") and (.VersionId | type == "string"))' \
            <<< "$request" >/dev/null || return 1
          printf '%s\n' "$request" >> "$test_dir/deleted"
          if [[ "$mode" == delete_failure ]]; then
            echo '{"Errors":[{"Code":"AccessDenied"}]}'
          else
            : # Quiet:true success: the AWS CLI prints nothing.
          fi ;;
        *) return 1 ;;
      esac
    }
    remediate_s3_versions test clusters "$s3_scanner" || exit 1
    [[ "$(< "$test_dir/page")" == 3 ]] || exit 1
    jq -se 'map(.Objects) | add | length == 501 and
      any(.[]; .VersionId == "marker1") and any(.[]; .VersionId == "null")' \
      "$test_dir/deleted" >/dev/null || exit 1
    printf '0\n' > "$test_dir/page"
    mode=delete_failure
    if remediate_s3_versions test clusters "$s3_scanner"; then exit 1; fi
    mode=list_failure
    if remediate_s3_versions test clusters "$s3_scanner"; then exit 1; fi
    calls=$(wc -l < "$test_dir/calls")
    if remediate_s3_versions test clusters 'Error: emptying S3 Bucket (bad;command)'; then exit 1; fi
    [[ "$(wc -l < "$test_dir/calls")" == "$calls" ]] || exit 1
  ); then
    _expect "S3 handler drains bounded pages, versions and markers; rejects API failures" ok ok
  else
    _expect "S3 handler drains bounded pages, versions and markers; rejects API failures" failed ok
  fi

  _expect "DependencyViolation -> vpc dependencies" \
    "$(classify_destroy_error "$dep_violation" clusters)" "remediate_vpc_dependencies"
  _expect "OIDC config in use -> state removal" \
    "$(classify_destroy_error "$oidc_in_use" clusters)" "remediate_orphaned_oidc"
  _expect "broken trust policy -> account roles" \
    "$(classify_destroy_error "$trust_policy" clusters)" "remediate_broken_trust_policy"
  _expect "DeleteConflict -> detach IAM policies" \
    "$(classify_destroy_error "$delete_conflict" cluster)" "remediate_iam_attachments"
  _expect "CLUSTERS-MGMT-404 -> already gone" \
    "$(classify_destroy_error "$gone" cluster)" "already_gone"
  _expect "InvalidGlobalClusterStateFault -> detach Aurora members" \
    "$(classify_destroy_error "$global_state" infra/terraform)" "remediate_aurora_global"
  _expect "last master instance after failover -> detach Aurora members" \
    "$(classify_destroy_error "$last_master" infra/terraform)" "remediate_aurora_global"
  _expect "EIP left on a deleted interface -> release it" \
    "$(classify_destroy_error "$stale_eip" vpc/terraform)" "remediate_stale_eips"

  _expect "log tag keeps a module path with a slash" \
    "$(printf 'x\n' | tag_stream e2e-run1 app/terraform)" "[e2e-run1][app/terraform] | x"

  # A 404 only means "already gone" for a cluster module; anywhere else it is
  # an unclassified failure and must not be swallowed as success.
  _expect "404 on a non-cluster module is not success" \
    "$(classify_destroy_error "$gone" backup_bucket)" ""
  _expect "unrecognised error has no handler" \
    "$(classify_destroy_error "$unknown" clusters)" ""

  # Every handler the classifier can name has to be callable, or the loop would
  # dispatch into nothing and the error would look recovered.
  for got in remediate_vpc_dependencies remediate_orphaned_oidc \
             remediate_broken_trust_policy remediate_iam_attachments \
             remediate_aurora_global remediate_s3_versions remediate_stale_eips; do
    if declare -F "$got" >/dev/null; then
      echo "ok   handler $got is defined"
    else
      echo "FAIL handler $got is named by the classifier but not defined"
      failures=$((failures + 1))
    fi
  done

  # cloud-nuke deletes whatever its config matches. An EKS entry left unscoped
  # would take every cluster in the CI account, not just this group's, so the
  # scoping is asserted rather than assumed.
  if command -v yq >/dev/null 2>&1; then
    local scoped_config scoped_vpc scoped_eks
    scoped_config="$(mktemp)"
    cp "$SCRIPT_DIR/matching-vpc.yml" "$scoped_config"
    NAME_REGEX='^example-group(-|$)' yq eval \
      '.VPC.include.names_regex = [strenv(NAME_REGEX)] | .EKSCluster.include.names_regex = [strenv(NAME_REGEX)]' \
      -i "$scoped_config"
    scoped_vpc="$(yq eval '.VPC.include.names_regex[0]' "$scoped_config")"
    scoped_eks="$(yq eval '.EKSCluster.include.names_regex[0]' "$scoped_config")"
    rm -f "$scoped_config"

    _expect "cloud-nuke VPC target is scoped to the group" "$scoped_vpc" '^example-group(-|$)'
    _expect "cloud-nuke EKS target is scoped to the group" "$scoped_eks" '^example-group(-|$)'

    # The boundary is the point: a prefix-only pattern also matches every
    # longer id, which is how one group's nuke reaches another's VPCs.
    if printf 'example-group-1234-r0-vpc\n' | grep -Eq '^example-group(-|$)' &&
       ! printf 'example-group1234-r0-vpc\n' | grep -Eq '^example-group(-|$)'; then
      echo "ok   cloud-nuke pattern stops at the group boundary"
    else
      echo "FAIL cloud-nuke pattern leaks across ids sharing a prefix"
      failures=$((failures + 1))
    fi
  else
    echo "skip cloud-nuke scoping check: yq unavailable"
  fi

  # Both target forms callers pass, and the boundary between ids that share
  # a prefix. The run-suffix form matched nothing for a while, which made the
  # Terratest suites' per-run cleanup a silent no-op.
  keys='p/tfstate-ecsdr-123/app/terraform.tfstate
p/tfstate-ecsdr-1234/app/terraform.tfstate
p/main/tfstate-ecsdr-123/vpc/terraform.tfstate
p/tfstate-e2e-p-abc-run987/app/terraform.tfstate
p/tfstate-e2e-u-abc-run987/infra/terraform.tfstate
p/tfstate-e2e-p-abc-run9876/app/terraform.tfstate'
  _expect "target selects its own cluster, not one sharing its prefix" \
    "$(printf '%s\n' "$keys" | select_target_groups ecsdr-123 | paste -sd, -)" "ecsdr-123"
  _expect "run-suffix target selects every group of that run, and only it" \
    "$(printf '%s\n' "$keys" | select_target_groups run987/ | paste -sd, -)" "e2e-p-abc-run987,e2e-u-abc-run987"

  # The last-module guard decides whether cloud-nuke may run at all. Nuking
  # before the VPC owner's turn deletes subnets and ENIs that the states still
  # queued behind it have in their own plans, so the guard is asserted against
  # a realistic ORDERED_MODULES rather than trusted.
  (
    RETRY_DESTROY=true
    CLEANUP_REGIONS="eu-west-2"
    # The permitted path goes on to `aws ec2 describe-vpcs` and `cloud-nuke`.
    # This runs as a pre-commit hook on machines that hold AWS credentials, so
    # both are replaced by fakes that only record the call: a selftest must
    # never be able to delete infrastructure.
    nuke_bin=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho vpc-0selftest\n' >"$nuke_bin/aws"
    printf '#!/usr/bin/env bash\necho "NUKE $*" >>"%s/calls"\n' "$nuke_bin" >"$nuke_bin/cloud-nuke"
    chmod +x "$nuke_bin/aws" "$nuke_bin/cloud-nuke"
    # Subshell-local on purpose, like ORDERED_MODULES below: the fakes must
    # not shadow the real tools for the rest of the script.
    # shellcheck disable=SC2030
    PATH="$nuke_bin:$PATH"
    # Subshell-local on purpose: the selftest must not leak its ORDERED_MODULES
    # into the real destruction order below.
    # shellcheck disable=SC2030
    ORDERED_MODULES=(app/terraform infra/terraform vpc/terraform fixture/terraform)
    # A greenfield group: every declared module but the BYO-VPC fixture.
    module_state_exists() { [[ "$2" != fixture/terraform ]]; }

    early=$(nuke_vpcs_in_cleanup_regions g infra/terraform "$(mktemp -d)" 2>&1)
    if [[ "$early" == *"Skipping the cloud-nuke fallback"* && ! -s "$nuke_bin/calls" ]]; then
      echo "ok   cloud-nuke skipped while a later module still owns the VPC"
    else
      echo "FAIL cloud-nuke ran for infra/terraform, before vpc/terraform was destroyed"; exit 1
    fi

    # vpc/terraform is the owner here even though fixture/terraform is declared
    # after it: the group has no fixture state. Gating on the declared order
    # skipped it, so greenfield groups never reached the fallback. Asserted on
    # the fake's record, so "ran" means cloud-nuke was really invoked.
    last=$(nuke_vpcs_in_cleanup_regions g vpc/terraform "$(mktemp -d)" 2>&1)
    if grep -q -- "--region eu-west-2" "$nuke_bin/calls" 2>/dev/null; then
      echo "ok   cloud-nuke runs for the module that owns the VPC"
    else
      echo "FAIL cloud-nuke never ran for the VPC owner: $last"; exit 1
    fi
  ) || failures=$((failures + 1))

  # The EIP lives in one of the declared regions, which the error does not
  # name. The handler has to find it there, drop the stale association and
  # release it, in that region — a release sent to the wrong region is a no-op
  # and the VPC still leaks.
  (
    eip_bin=$(mktemp -d)
    cat >"$eip_bin/aws" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_CALLS"
case "$*" in
  *"describe-addresses --region eu-west-3"*) echo "eipassoc-08223567b1693755f" ;;
  *describe-addresses*) exit 254 ;;
esac
FAKE
    chmod +x "$eip_bin/aws"
    # Each case owns its subshell and its own call log, like PATH above.
    # shellcheck disable=SC2030
    export FAKE_CALLS="$eip_bin/calls"
    : >"$FAKE_CALLS"
    # shellcheck disable=SC2030,SC2031
    PATH="$eip_bin:$PATH"
    CLEANUP_REGIONS="eu-west-2 eu-west-3"

    remediate_stale_eips g vpc/terraform "$stale_eip" >/dev/null 2>&1
    if grep -q "disassociate-address --region eu-west-3 --association-id eipassoc-08223567b1693755f" "$FAKE_CALLS" &&
       grep -q "release-address --region eu-west-3 --allocation-id eipalloc-05ae99ac0dafa1cf0" "$FAKE_CALLS" &&
       ! grep -q "release-address --region eu-west-2" "$FAKE_CALLS"; then
      echo "ok   stale EIP is disassociated and released in its own region"
    else
      echo "FAIL stale EIP handler did not release it in eu-west-3:"; cat "$FAKE_CALLS"
      exit 1
    fi
  ) || failures=$((failures + 1))

  # The instance-lookup branch resolves an instance name to a global cluster
  # through three chained describe calls. A wrong ARN field index or regex
  # yields an empty result, the handler reports "nothing to detach" and
  # returns 0, and the retry loop then exhausts itself with the global cluster
  # still blocking the destroy — silently, and billing throughout.
  (
    fake_bin=$(mktemp -d)
    cat >"$fake_bin/aws" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"describe-global-clusters --query"*) echo "my-global-db" ;;
  *"--global-cluster-identifier my-global-db --query"*)
    echo "arn:aws:rds:eu-west-3:1:cluster:member-r1" ;;
  # Region-sensitive on purpose: the member lives in eu-west-3, so a lookup
  # that reads the wrong ARN field queries the wrong region and finds nothing.
  *"describe-db-clusters --region eu-west-3 --db-cluster-identifier member-r1"*) echo "the-instance" ;;
  *describe-db-clusters*) ;;
  *remove-from-global-cluster*) echo "REMOVE $*" >>"$FAKE_CALLS" ;;
esac
FAKE
    chmod +x "$fake_bin/aws"
    # shellcheck disable=SC2031  # this case's own call log, see the EIP case
    export FAKE_CALLS="$fake_bin/calls"
    : >"$FAKE_CALLS"
    # SC2031: each case gets its own subshell and its own fakes; the PATH set
    # in the cloud-nuke case above never reaches this one, by design.
    # shellcheck disable=SC2031
    PATH="$fake_bin:$PATH"

    # No "RDS Global Cluster (...)" in the text, so only the instance-lookup
    # branch can find the owner.
    err_text="Error: deleting RDS Cluster Instance (the-instance): Cannot delete the last instance of the master cluster"
    out=$(remediate_aurora_global g infra/terraform "$err_text" 2>&1)

    # The region matters as much as the ARN: remove-from-global-cluster has to
    # go to the member's own region, which after a failover is not AWS_REGION.
    if grep -q "remove-from-global-cluster" "$FAKE_CALLS" &&
       grep -q -- "--region eu-west-3" "$FAKE_CALLS" &&
       grep -q "arn:aws:rds:eu-west-3:1:cluster:member-r1" "$FAKE_CALLS"; then
      echo "ok   Aurora handler resolves a global cluster from the instance name"
    else
      echo "FAIL Aurora handler detached nothing from an instance-only error: $out"
      exit 1
    fi
  ) || failures=$((failures + 1))

  [[ "$failures" -eq 0 ]] || return 1
}

if [[ "$SELFTEST" == true ]]; then
  destroy_selftest
  exit $?
fi

# Fetch all group IDs
all_objects=$(aws s3 ls "s3://$BUCKET/$KEY_PREFIX" --recursive)
aws_exit_code=$?

# `aws s3 ls` exits 1 when the prefix holds no object, which is not an error
# here, and 255 when the call itself fails: expired credentials, no network, a
# denied bucket. The previous condition only tripped when stdout was non-empty,
# but a failed call writes to stderr and leaves stdout empty, so it was
# indistinguishable from an empty prefix and would be reported below as
# "nothing to destroy" — a green run that reclaimed nothing.
if [ $aws_exit_code -ne 0 ] && [ $aws_exit_code -ne 1 ]; then
  echo "Error executing aws s3 ls (Exit Code: $aws_exit_code)." >&2
  exit 1
fi

# `tf-bucket-key-prefix` defaults to empty, in which case the keys start with
# `tfstate-<group>/` and have no leading slash at all. Anchoring on `/tfstate-`
# silently matched nothing for those callers, and a targeted cleanup then
# reported "nothing to destroy" and exited 0 with the stack still running.
# `(^|.*/)` accepts the key either at the root or behind a prefix; it is
# written as an ERE because BRE alternation is a GNU extension and this
# script has to run outside GNU userland.
if [ "$ID_OR_ALL" == "all" ]; then
  groups=$(echo "$all_objects" | awk '{print $NF}' | sed -E -n 's#(^|.*/)tfstate-([^/]*)/.*#\2#p' | sort -u)
else
  groups=$(echo "$all_objects" | awk '{print $NF}' | select_target_groups "$ID_OR_ALL")
  if [ -z "$groups" ] && [ "$FAIL_ON_NOT_FOUND" = true ]; then
    echo "Error: No object found for ID '$ID_OR_ALL'"
    exit 1
  fi
fi

# Without this the loop below iterates zero times and the script still reports
# "All operations completed successfully", which reads as a successful destroy.
if [ -z "$groups" ]; then
  echo "No terraform state found for target '$ID_OR_ALL' under s3://$BUCKET/$KEY_PREFIX; nothing to destroy."
  exit 0
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
    # SC2031: the only writer is the selftest subshell above, which exits
    # before this runs and is isolated precisely so it cannot reach here.
    # shellcheck disable=SC2031
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
          # The modules below this one hold resources it depends on: destroying
          # them under a live state fails (a VPC still holding RDS ENIs), so
          # leave the rest of the group for a later run.
          echo "[$group_id][$module] Skipping it and the modules after it (age < $MIN_AGE_IN_HOURS hours)"
          break
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

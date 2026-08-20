#!/bin/bash
set -euo pipefail

# Description:
# This script deletes ROSA clusters that have no resources left in AWS but still appear in the OpenShift console.
# It ensures that only clusters older than a specified number of hours (MIN_AGE) are deleted.

# Check if required environment variables are set
if [ -z "$RHCS_TOKEN" ]; then
  echo "Error: The environment variable RHCS_TOKEN is not set."
  exit 1
fi

# Check if MIN_AGE (in hours) is provided
if [ $# -lt 1 ]; then
  echo "❌ Usage: $0 <MIN_AGE in hours>"
  exit 1
fi


# Detect operating system and set the appropriate date command
if [[ "$(uname)" == "Darwin" ]]; then
    date_command="gdate"
else
    date_command="date"
fi

MIN_AGE_HOURS=$1
CURRENT_TIME=$($date_command +%s)
FAILED=0

# How long to wait for OCM to deregister a cluster before giving up on it.
# Overridable so the behaviour can be exercised without a 30 minute wait.
DEREGISTER_MAX_ATTEMPTS="${DEREGISTER_MAX_ATTEMPTS:-60}"
DEREGISTER_INTERVAL="${DEREGISTER_INTERVAL:-30}"


# cleanup_iam_roles_with_prefix removes all IAM roles whose name starts with the
# given prefix, including detaching/deleting their policies first.
cleanup_iam_roles_with_prefix() {
  local role_prefix="$1"
  local roles
  roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${role_prefix}')].RoleName" --output text)
  if [[ -z "$roles" || "$roles" == "None" ]]; then
    echo "  ℹ️ No IAM roles found for prefix ${role_prefix}, already cleaned up"
    return 0
  fi
  for role in $roles; do
    echo "  🗑️ Cleaning up IAM role: $role"
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text)
    if [[ -n "$attached_policies" && "$attached_policies" != "None" ]]; then
      for policy_arn in $attached_policies; do
        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
      done
    fi
    local inline_policies
    inline_policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text)
    if [[ -n "$inline_policies" && "$inline_policies" != "None" ]]; then
      for policy_name in $inline_policies; do
        aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name"
      done
    fi
    aws iam delete-role --role-name "$role"
    echo "  ✅ Deleted role: $role"
  done
}

rosa login --token="$RHCS_TOKEN"

# Ensure account-level OCM roles exist (prerequisites for cluster operations)
echo "📦 Ensuring account-roles exist..."
rosa create account-roles --mode auto --yes
echo "📦 Ensuring ocm-role exists..."
rosa create ocm-role --mode auto --yes

# installer_role_missing reports whether a cluster has lost the account role OCM
# assumes to tear it down. Without it `rosa delete cluster` returns
# CLUSTERS-MGMT-400 and terraform can never remove the VPC, so the cluster, its
# subnets and its Elastic IPs stay allocated indefinitely.
installer_role_missing() {
  local cluster_name="$1"
  ! aws iam get-role --role-name "${cluster_name}-account-HCP-ROSA-Installer-Role" >/dev/null 2>&1
}

all_clusters=$(rosa list cluster --output json)

# A cluster is a candidate when it shows one of the shapes a failed teardown
# leaves behind:
#   - a ghost: no node pool left and a single limited-support reason;
#   - error;
#   - uninstalling, i.e. a deletion that started and never finished.
# The age gate in the loop below still applies to all of them.
candidates=$(echo "$all_clusters" | jq -c '[.[] | select(
     ((.node_pools.items | length == 0) and .status.limited_support_reason_count == 1)
  or (.status.state == "error")
  or (.status.state == "uninstalling")
)]')

# The fourth shape cannot be expressed in jq because it needs an IAM lookup: a
# cluster in any state whose installer role has gone missing is already
# undeletable, and is the case this script exists to repair.
orphaned=$(echo "$all_clusters" | jq -c '.[]' | while read -r cluster; do
  name=$(echo "$cluster" | jq -r '.name')
  if installer_role_missing "$name"; then
    echo "$cluster"
  fi
done | jq -c -s '.')

raw_clusters=$(jq -c -n --argjson a "$candidates" --argjson b "$orphaned" '$a + $b | unique_by(.id)')

# Check if there are any clusters
cluster_count=$(echo "$raw_clusters" | jq 'length')

if [ "$cluster_count" -eq 0 ]; then
  echo "✅ No clusters to delete. Exiting."
  exit 0
fi

# Fed through process substitution rather than a pipe: a piped `while` runs in a
# subshell, where the FAILED flag set below would be discarded at the end of the
# loop and the script would exit 0 despite leaving roles behind.
while read -r cluster; do
  cluster_id=$(echo "$cluster" | jq -r '.id')
  cluster_name=$(echo "$cluster" | jq -r '.name')
  region_id=$(echo "$cluster" | jq -r '.region.id')
  oidc_config_id=$(echo "$cluster" | jq -r '.aws.sts.oidc_config.id')
  creation_timestamp=$(echo "$cluster" | jq -r '.creation_timestamp')

  # Convert creation timestamp to UNIX time
  cluster_created_time=$($date_command -d "$creation_timestamp" +%s)
  cluster_age_hours=$(( (CURRENT_TIME - cluster_created_time) / 3600 ))

  if [ "$cluster_age_hours" -lt "$MIN_AGE_HOURS" ]; then
    echo "⏳ Cluster $cluster_name is too recent (${cluster_age_hours}h < ${MIN_AGE_HOURS}h). Skipping."
    continue
  fi



  echo "----------------------------------------"
  echo "🔧 Cluster ID: $cluster_id"
  echo "🔧 Cluster Name: $cluster_name"
  echo "🌍 Region: $region_id"

  echo "📦 Recreating account roles with prefix ${cluster_name}-account"
  AWS_REGION="$region_id" rosa create account-roles --mode auto --yes --hosted-cp --prefix "${cluster_name}-account"

  installer_role_arn=$(aws iam get-role --role-name "${cluster_name}-account-HCP-ROSA-Installer-Role" --query 'Role.Arn' --output text)

  echo "📦 Recreating operator roles with prefix ${cluster_name}-operator"
  AWS_REGION="$region_id" rosa create operator-roles --mode auto --yes --hosted-cp --prefix "${cluster_name}-operator" --oidc-config-id "${oidc_config_id}" --role-arn "${installer_role_arn}"

  echo "💣 Deleting cluster: $cluster_name"
  # Do NOT pass --watch: it blocks for the full ~60 min AWS teardown and
  # starves later clusters in the matrix. The polling loop below is the
  # supported wait mechanism.
  AWS_REGION="$region_id" rosa delete cluster -c "$cluster_name" -y --best-effort

  # Wait for the cluster to be fully deregistered from ROSA API
  # rosa delete cluster can return before the cluster is fully removed,
  # which causes operator-roles deletion to fail with "clusters using Operator Roles Prefix"
  echo "⏳ Waiting for cluster $cluster_name to be fully deregistered..."
  cluster_deregistered=false
  for i in $(seq 1 "$DEREGISTER_MAX_ATTEMPTS"); do
    # Capture `rosa list clusters` separately so we can distinguish a
    # transient failure (API/network hiccup) from a true "cluster not found".
    # Treating a non-zero `rosa list` as deregistered would let role deletion
    # race ahead of cluster teardown and fail with
    # "clusters using Operator Roles Prefix".
    if cluster_list=$(rosa list clusters 2>/dev/null); then
      if echo "$cluster_list" | grep -q "[[:space:]]${cluster_name}[[:space:]]"; then
        if [ "$i" -lt "$DEREGISTER_MAX_ATTEMPTS" ]; then
          echo "⏳ Cluster still registered, waiting ${DEREGISTER_INTERVAL}s... (attempt $i/${DEREGISTER_MAX_ATTEMPTS})"
          sleep "$DEREGISTER_INTERVAL"
        else
          echo "❌ Cluster $cluster_name is still registered after $i attempts"
        fi
      else
        echo "✅ Cluster $cluster_name is fully deregistered"
        cluster_deregistered=true
        break
      fi
    else
      echo "⚠️ rosa list clusters failed transiently, retrying in ${DEREGISTER_INTERVAL}s... (attempt $i/${DEREGISTER_MAX_ATTEMPTS})"
      sleep "$DEREGISTER_INTERVAL"
    fi
  done

  if [ "$cluster_deregistered" != true ]; then
    # Deleting the IAM roles now would strip the installer role OCM needs to
    # finish the deletion, turning a cluster that is merely slow into one that
    # can never be removed: `rosa delete cluster` then returns
    # CLUSTERS-MGMT-400, terraform can never delete the VPC, and its Elastic IPs
    # stay allocated until someone recreates the roles by hand. Leave them and
    # let the next run try again, once the cluster has finished uninstalling.
    echo "⚠️ Cluster $cluster_name is still registered; leaving its IAM roles in place."
    echo "   Removing them while OCM still owns the cluster is what makes a cluster undeletable."
    FAILED=1
    continue
  fi

  echo "🧹 Deleting operator roles with prefix ${cluster_name}-operator"
  # Safe to use the rosa CLI here: the cluster is deregistered, so it cannot fail
  # with "clusters using Operator Roles Prefix".
  if ! AWS_REGION="$region_id" rosa delete operator-roles --prefix "${cluster_name}-operator" --yes --mode auto; then
    echo "⚠️ rosa delete operator-roles failed, falling back to direct AWS IAM cleanup"
    cleanup_iam_roles_with_prefix "${cluster_name}-operator"
  fi

  echo "🧹 Deleting account roles with prefix ${cluster_name}-account"
  if ! AWS_REGION="$region_id" rosa delete account-roles --prefix "${cluster_name}-account" --yes --mode auto; then
    echo "⚠️ rosa delete account-roles failed, falling back to direct AWS IAM cleanup"
    cleanup_iam_roles_with_prefix "${cluster_name}-account"
  fi

  echo "🧹 Deleting OIDC provider ${oidc_config_id}"
  if ! AWS_REGION="$region_id" rosa delete oidc-provider --oidc-config-id "${oidc_config_id}" --yes --mode auto; then
    echo "⚠️ rosa delete oidc-provider failed, falling back to direct AWS IAM cleanup"
    oidc_provider_arn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '/${oidc_config_id}')].Arn" --output text)
    if [[ -n "$oidc_provider_arn" && "$oidc_provider_arn" != "None" ]]; then
      echo "  🗑️ Deleting OIDC provider: $oidc_provider_arn"
      aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$oidc_provider_arn"
      echo "  ✅ Deleted OIDC provider: $oidc_provider_arn"
    else
      echo "  ℹ️ No OIDC provider found for config ID ${oidc_config_id}, already cleaned up"
    fi
  fi

done < <(echo "$raw_clusters" | jq -c '.[]')

if [ "$FAILED" -ne 0 ]; then
  echo "❌ At least one cluster could not be fully cleaned up; its IAM roles were left in place."
  exit 1
fi

echo "✅ All clusters have been deleted!"

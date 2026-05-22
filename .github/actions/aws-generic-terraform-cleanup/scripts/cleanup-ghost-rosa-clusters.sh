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

# Fetch clusters matching the criteria (if no node pool and error reported)
raw_clusters=$(rosa list cluster --output json | jq '[.[] | select((.node_pools.items | length == 0) and .status.limited_support_reason_count == 1 or .status.state == "error")]')

# Check if there are any clusters
cluster_count=$(echo "$raw_clusters" | jq 'length')

if [ "$cluster_count" -eq 0 ]; then
  echo "✅ No clusters to delete. Exiting."
  exit 0
fi

echo "$raw_clusters" | jq -c '.[]' | while read -r cluster; do
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
  for i in $(seq 1 60); do
    # Distinguish "cluster not found" from transient errors by checking if the
    # cluster still appears in the list of clusters. If it does not, we assume
    # it is fully deregistered; otherwise, we keep waiting.
    if rosa list clusters 2>/dev/null | grep -q "[[:space:]]${cluster_name}[[:space:]]"; then
      if [ "$i" -lt 60 ]; then
        echo "⏳ Cluster still registered, waiting 30s... (attempt $i/60)"
        sleep 30
      else
        echo "❌ Cluster $cluster_name is still registered after $i attempts"
      fi
    else
      echo "✅ Cluster $cluster_name is fully deregistered"
      cluster_deregistered=true
      break
    fi
  done

  if [ "$cluster_deregistered" != true ]; then
    echo "⚠️ Cluster $cluster_name did not deregister in time. Proceeding with direct IAM cleanup..."
  fi

  echo "🧹 Deleting operator roles with prefix ${cluster_name}-operator"
  if [ "$cluster_deregistered" == true ]; then
    # Only try rosa CLI if the cluster is fully deregistered, otherwise it will fail
    # with "clusters using Operator Roles Prefix"
    if ! AWS_REGION="$region_id" rosa delete operator-roles --prefix "${cluster_name}-operator" --yes --mode auto; then
      echo "⚠️ rosa delete operator-roles failed, falling back to direct AWS IAM cleanup"
      cleanup_iam_roles_with_prefix "${cluster_name}-operator"
    fi
  else
    echo "⚠️ Cluster still registered, falling back to direct AWS IAM cleanup for operator roles"
    cleanup_iam_roles_with_prefix "${cluster_name}-operator"
  fi

  echo "🧹 Deleting account roles with prefix ${cluster_name}-account"
  if [ "$cluster_deregistered" == true ]; then
    if ! AWS_REGION="$region_id" rosa delete account-roles --prefix "${cluster_name}-account" --yes --mode auto; then
      echo "⚠️ rosa delete account-roles failed, falling back to direct AWS IAM cleanup"
      cleanup_iam_roles_with_prefix "${cluster_name}-account"
    fi
  else
    echo "⚠️ Cluster still registered, falling back to direct AWS IAM cleanup for account roles"
    cleanup_iam_roles_with_prefix "${cluster_name}-account"
  fi

  echo "🧹 Deleting OIDC provider ${oidc_config_id}"
  if [ "$cluster_deregistered" == true ]; then
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
  else
    echo "⚠️ Cluster still registered, falling back to direct AWS IAM cleanup for OIDC provider"
    oidc_provider_arn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '/${oidc_config_id}')].Arn" --output text)
    if [[ -n "$oidc_provider_arn" && "$oidc_provider_arn" != "None" ]]; then
      echo "  🗑️ Deleting OIDC provider: $oidc_provider_arn"
      aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$oidc_provider_arn"
      echo "  ✅ Deleted OIDC provider: $oidc_provider_arn"
    else
      echo "  ℹ️ No OIDC provider found for config ID ${oidc_config_id}, already cleaned up"
    fi
  fi

done

echo "✅ All clusters have been deleted!"

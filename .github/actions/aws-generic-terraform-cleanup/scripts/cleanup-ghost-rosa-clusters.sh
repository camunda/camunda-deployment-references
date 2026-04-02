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
  AWS_REGION="$region_id" rosa delete cluster -c "$cluster_name" -y --watch

  # Wait for the cluster to be fully deregistered from ROSA API
  # rosa delete cluster --watch can return before the cluster is fully removed,
  # which causes operator-roles deletion to fail with "clusters using Operator Roles Prefix"
  echo "⏳ Waiting for cluster $cluster_name to be fully deregistered..."
  for i in $(seq 1 12); do
    if ! rosa describe cluster -c "$cluster_name" &>/dev/null; then
      echo "✅ Cluster $cluster_name is fully deregistered"
      break
    fi
    echo "⏳ Cluster still registered, waiting 30s... (attempt $i/12)"
    sleep 30
  done

  echo "🧹 Deleting operator roles with prefix ${cluster_name}-operator"
  for i in $(seq 1 6); do
    if AWS_REGION="$region_id" rosa delete operator-roles --prefix "${cluster_name}-operator" --yes --mode auto; then
      break
    fi
    echo "⚠️ Failed to delete operator roles, retrying in 30s... (attempt $i/6)"
    sleep 30
  done

  echo "🧹 Deleting account roles with prefix ${cluster_name}-account"
  AWS_REGION="$region_id" rosa delete account-roles --prefix "${cluster_name}-account" --yes --mode auto

  echo "🧹 Deleting OIDC provider ${oidc_config_id}"
  AWS_REGION="$region_id" rosa delete oidc-provider --oidc-config-id "${oidc_config_id}" --yes --mode auto

done

echo "✅ All clusters have been deleted!"

#!/bin/bash
set -euo pipefail

# Description:
# This script deletes clusters that are in a state where no resources are left in AWS, but are still reported in the OpenShift console.
# This is often due to a "nuke" destruction action that leaves the cluster in an inconsistent state.

# Check if required environment variables are set
if [ -z "$RHCS_TOKEN" ]; then
  echo "Error: The environment variable RHCS_TOKEN is not set."
  exit 1
fi

rosa login --token="$RHCS_TOKEN"

# Fetch clusters matching the criteria (if no node pool and error reported)
raw_clusters=$(rosa list cluster --output json | jq '[.[] | select((.node_pools.items | length == 0) and .status.limited_support_reason_count == 1)]')

# Check if there are any clusters
cluster_count=$(echo "$raw_clusters" | jq 'length')

if [ "$cluster_count" -eq 0 ]; then
  echo "✅ No clusters to delete. Exiting."
  exit 0
fi

echo "$raw_clusters" | jq -c '.[]' | while read -r cluster; do
  cluster_id=$(echo "$cluster" | jq -r '.id')
  cluser_name=$(echo "$cluster" | jq -r '.name')
  region_id=$(echo "$cluster" | jq -r '.region.id')
  oidc_config_id=$(echo "$cluster" | jq -r '.aws.sts.oidc_config.id')

  echo "----------------------------------------"
  echo "🔧 Cluster ID: $cluster_id"
  echo "🔧 Cluster Name: $cluser_name"
  echo "🌍 Region: $region_id"

  echo "📦 Recreating account roles with prefix ${cluser_name}-account"
  AWS_REGION="$region_id" rosa create account-roles --mode auto --yes --hosted-cp --prefix "${cluser_name}-account"

  echo "📦 Recreating operator roles with prefix ${cluser_name}-account"
  AWS_REGION="$region_id" rosa create operator-roles --mode auto --yes --hosted-cp --prefix "${cluser_name}-account"

  echo "💣 Deleting cluster: $cluser_name"
  AWS_REGION="$region_id" rosa delete cluster -c "$cluser_name" -y --watch


  AWS_REGION="$region_id" rosa delete operator-roles --prefix "${cluser_name}-operator" --yes --mode auto
  AWS_REGION="$region_id" rosa delete oidc-provider --oidc-config-id "${oidc_config_id}" --yes --mode auto

done

echo "✅ All clusters have been deleted!"

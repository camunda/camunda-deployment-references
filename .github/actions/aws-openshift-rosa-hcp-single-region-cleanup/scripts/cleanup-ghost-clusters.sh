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

# Fetch clusters matching the criteria
raw_clusters=$(rosa list cluster --output json | jq '[.[] | select((.node_pools.items | length == 0) and .status.limited_support_reason_count == 1)]')

# Check if there are any clusters
cluster_count=$(echo "$raw_clusters" | jq 'length')

if [ "$cluster_count" -eq 0 ]; then
  echo "✅ No clusters to delete. Exiting."
  exit 0
fi

# For each cluster object
echo "$raw_clusters" | jq -c '.[]' | while read -r cluster; do
  # Extract cluster ID and region ID using jq
  cluster_id=$(echo "$cluster" | jq -r '.id')
  cluser_name=$(echo "$cluster" | jq -r '.name')
  region_id=$(echo "$cluster" | jq -r '.region.id')

  echo "----------------------------------------"
  echo "🔧 Cluster ID: $cluster_id"
  echo "🔧 Cluster Name: $cluser_name"
  echo "🌍 Region: $region_id"

  echo "📦 Recreating account roles with prefix ${cluser_name}-account"
  AWS_REGION="$region_id" rosa create account-roles --mode auto --yes --prefix "${cluser_name}-account"

  echo "💣 Deleting cluster: $cluser_name"
  AWS_REGION="$region_id" rosa delete cluster -c "$cluser_name" -y --watch

done

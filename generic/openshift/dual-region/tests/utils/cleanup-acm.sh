#!/usr/bin/env bash

# Cleanup script for ACM (Advanced Cluster Management) and related resources
# This script ensures a completely clean state before installing ACM

set -euo pipefail

# Helper function to remove finalizers and force delete a resource
force_delete_resource() {
  local context=$1
  local resource_type=$2
  local resource_name=$3
  local namespace=${4:-}

  local ns_flag=""
  if [ -n "$namespace" ]; then
    ns_flag="-n $namespace"
  fi

  # shellcheck disable=SC2086
  oc --context "$context" patch "$resource_type" "$resource_name" $ns_flag \
    --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  # shellcheck disable=SC2086
  oc --context "$context" delete "$resource_type" "$resource_name" $ns_flag \
    --grace-period=0 --force 2>/dev/null || true
}

# Helper function to print list items
print_list() {
  while IFS= read -r item; do
    [ -n "$item" ] && echo "  - $item"
  done <<< "$1"
}

# Check required environment variables
if [ -z "${CLUSTER_1_NAME:-}" ]; then
  echo "❌ ERROR: CLUSTER_1_NAME environment variable is not set"
  exit 1
fi

if [ -z "${CLUSTER_2_NAME:-}" ]; then
  echo "❌ ERROR: CLUSTER_2_NAME environment variable is not set"
  exit 1
fi

echo "🧹 Starting comprehensive ACM cleanup for fresh installation..."
echo "================================================================"
echo ""

CLUSTERS=("local-cluster" "$CLUSTER_2_NAME")

# Step 1: Delete all ManagedClusters (aggressive mode - no waiting)
echo "Step 1: Deleting all ManagedClusters..."
echo "----------------------------------------"
for cluster_name in "${CLUSTERS[@]}"; do
  if oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" >/dev/null 2>&1; then
    echo "🗑️  Force deleting ManagedCluster: $cluster_name"
    force_delete_resource "$CLUSTER_1_NAME" "managedcluster" "$cluster_name"
    echo "  ✅ ManagedCluster '$cluster_name' deletion initiated"
  else
    echo "  ℹ️  ManagedCluster '$cluster_name' not found - skipping"
  fi
done
echo ""

# Step 2: Clean up cluster-specific and ACM/Submariner namespaces (parallel deletion)
echo "Step 2: Cleaning up ACM and Submariner namespaces on hub..."
echo "------------------------------------------------------------"
NAMESPACES_TO_DELETE=(
  "${CLUSTERS[@]}"
  "open-cluster-management-global-set"
  "open-cluster-management-hub"
  "multicluster-engine"
  "hive"
  "submariner-operator"
  "submariner-k8s-broker"
  "open-cluster-management-addon"
  "open-cluster-management-observability"
  "open-cluster-management-backup"
)

for ns in "${NAMESPACES_TO_DELETE[@]}"; do
  if oc --context "$CLUSTER_1_NAME" get namespace "$ns" >/dev/null 2>&1; then
    echo "🗑️  Force deleting namespace: $ns"
    oc --context "$CLUSTER_1_NAME" patch namespace "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true &
    oc --context "$CLUSTER_1_NAME" delete namespace "$ns" --grace-period=0 2>/dev/null || true &
  fi
done
wait  # Wait for all parallel namespace deletions to start
echo "  ✅ Namespace deletion initiated for all ACM/Submariner namespaces"
echo ""

# Step 3: Clean up klusterlet and agent resources on managed clusters (parallel)
echo "Step 3: Cleaning up klusterlet and agent resources..."
echo "------------------------------------------------------"

# Function to clean agent namespaces on a cluster
cleanup_agent_namespaces() {
  local context=$1
  local cluster_label=$2

  for ns in open-cluster-management-agent open-cluster-management-agent-addon submariner-operator; do
    if oc --context "$context" get namespace "$ns" >/dev/null 2>&1; then
      echo "🗑️  Force deleting $ns on $cluster_label"
      oc --context "$context" patch namespace "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      oc --context "$context" delete namespace "$ns" --grace-period=0 2>/dev/null || true
    fi
  done

  # Delete klusterlet CRs
  if oc --context "$context" get klusterlet >/dev/null 2>&1; then
    echo "🗑️  Deleting klusterlet CRs on $cluster_label"
    for kl in $(oc --context "$context" get klusterlet -o name 2>/dev/null); do
      oc --context "$context" patch "$kl" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      oc --context "$context" delete "$kl" --grace-period=0 --force 2>/dev/null || true
    done
  fi
}

# Clean both clusters in parallel
cleanup_agent_namespaces "$CLUSTER_1_NAME" "cluster 1" &
cleanup_agent_namespaces "$CLUSTER_2_NAME" "cluster 2" &
wait
echo "  ✅ Agent namespace cleanup initiated on both clusters"
echo ""

# Step 4: Delete ManagedClusterSet and related resources (fast)
echo "Step 4: Deleting ManagedClusterSet..."
echo "-------------------------------------"
if oc --context="$CLUSTER_1_NAME" get managedclusterset camunda-zeebe >/dev/null 2>&1; then
  echo "🗑️  Force deleting ManagedClusterSet: camunda-zeebe"
  force_delete_resource "$CLUSTER_1_NAME" "managedclusterset" "camunda-zeebe"
fi

if oc --context="$CLUSTER_1_NAME" get managedclustersetbinding camunda-zeebe -n open-cluster-management >/dev/null 2>&1; then
  echo "🗑️  Force deleting ManagedClusterSetBinding: camunda-zeebe"
  force_delete_resource "$CLUSTER_1_NAME" "managedclustersetbinding" "camunda-zeebe" "open-cluster-management"
fi
echo ""

# Step 5: Delete MultiClusterHub (fast, no waiting)
echo "Step 5: Deleting MultiClusterHub..."
echo "------------------------------------"
oc --context="$CLUSTER_1_NAME" delete clusterrole open-cluster-management:cluster-manager-admin 2>/dev/null || true

if oc --context="$CLUSTER_1_NAME" get multiclusterhub -n open-cluster-management >/dev/null 2>&1; then
  echo "🗑️  Force deleting MultiClusterHub instances"
  for mch in $(oc --context="$CLUSTER_1_NAME" get multiclusterhub -n open-cluster-management -o name 2>/dev/null); do
    mch_name=$(echo "$mch" | cut -d'/' -f2)
    force_delete_resource "$CLUSTER_1_NAME" "multiclusterhub" "$mch_name" "open-cluster-management"
  done
  echo "  ✅ MultiClusterHub deletion initiated"
else
  echo "  ℹ️  MultiClusterHub not found - skipping"
fi
echo ""

# Step 6: Delete ACM Operator Subscription and CSV (fast)
echo "Step 6: Deleting ACM Operator..."
echo "---------------------------------"
if oc --context="$CLUSTER_1_NAME" get subscription advanced-cluster-management -n open-cluster-management >/dev/null 2>&1; then
  echo "🗑️  Force deleting ACM subscription"
  force_delete_resource "$CLUSTER_1_NAME" "subscription" "advanced-cluster-management" "open-cluster-management"
fi

# Delete ClusterServiceVersion (CSV) for ACM
if oc --context="$CLUSTER_1_NAME" get csv -n open-cluster-management 2>/dev/null | grep -q advanced-cluster-management; then
  echo "🗑️  Force deleting ACM ClusterServiceVersions"
  for csv in $(oc --context="$CLUSTER_1_NAME" get csv -n open-cluster-management -o name 2>/dev/null | grep advanced-cluster-management); do
    csv_name=$(echo "$csv" | cut -d'/' -f2)
    force_delete_resource "$CLUSTER_1_NAME" "csv" "$csv_name" "open-cluster-management"
  done
fi
echo ""

# Step 7: Delete MultiClusterEngine (fast, no waiting)
echo "Step 7: Deleting MultiClusterEngine..."
echo "---------------------------------------"
if oc --context="$CLUSTER_1_NAME" get multiclusterengine -n open-cluster-management >/dev/null 2>&1; then
  echo "🗑️  Force deleting MultiClusterEngine instances"
  for mce in $(oc --context="$CLUSTER_1_NAME" get multiclusterengine -n open-cluster-management -o name 2>/dev/null); do
    mce_name=$(echo "$mce" | cut -d'/' -f2)
    force_delete_resource "$CLUSTER_1_NAME" "multiclusterengine" "$mce_name" "open-cluster-management"
  done
  echo "  ✅ MultiClusterEngine deletion initiated"
else
  echo "  ℹ️  MultiClusterEngine not found - skipping"
fi
echo ""

# Step 8: Force delete remaining ACM-related namespaces (fast, no waiting per namespace)
echo "Step 8: Force deleting remaining ACM-related namespaces..."
echo "-----------------------------------------------------------"

# Get all ACM-related namespaces
ACM_NAMESPACES=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name 2>/dev/null | grep -E 'namespace/(open-cluster-management|multicluster-engine)' | sed 's|namespace/||' || echo "")

if [ -n "$ACM_NAMESPACES" ]; then
  echo "Found ACM-related namespaces:"
  print_list "$ACM_NAMESPACES"
  echo ""

  for ns in $ACM_NAMESPACES; do
    if oc --context="$CLUSTER_1_NAME" get namespace "$ns" >/dev/null 2>&1; then
      echo "🗑️  Force deleting namespace: $ns"

      # Special handling for open-cluster-management namespace
      if [ "$ns" = "open-cluster-management" ]; then
        # Remove finalizers from search resources
        for search in $(oc --context="$CLUSTER_1_NAME" get searches.search.open-cluster-management.io -n "$ns" -o name 2>/dev/null); do
          oc --context="$CLUSTER_1_NAME" patch "$search" -n "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true &
        done
      fi

      # Force delete namespace immediately (no waiting)
      oc --context="$CLUSTER_1_NAME" patch namespace "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      oc --context="$CLUSTER_1_NAME" delete namespace "$ns" --grace-period=0 2>/dev/null || true
    fi
  done
  wait  # Wait for all parallel operations
  echo "  ✅ Namespace deletion initiated for all ACM namespaces"
else
  echo "ℹ️  No ACM-related namespaces found"
fi
echo ""

# Step 9: Clean up ACM and Submariner cluster-scoped resources (parallel)
echo "Step 9: Cleaning up cluster-scoped resources..."
echo "------------------------------------------------"

# Run all cluster-scoped cleanup in parallel for speed
(
  echo "🗑️  Removing ACM-related ClusterRoles and ClusterRoleBindings"
  oc --context="$CLUSTER_1_NAME" delete clusterrole -l open-cluster-management.io/aggregate-to-work= --grace-period=0 2>/dev/null || true
  oc --context="$CLUSTER_1_NAME" delete clusterrolebinding -l open-cluster-management.io/aggregate-to-work= --grace-period=0 2>/dev/null || true
) &

(
  echo "🗑️  Removing Submariner-related resources on cluster 1"
  oc --context="$CLUSTER_1_NAME" delete clusterrole -l app=submariner --grace-period=0 2>/dev/null || true
  oc --context="$CLUSTER_1_NAME" delete clusterrolebinding -l app=submariner --grace-period=0 2>/dev/null || true
  # Delete Submariner CRDs
  submariner_crds=$(oc --context="$CLUSTER_1_NAME" get crd 2>/dev/null | grep submariner | awk '{print $1}')
  if [ -n "$submariner_crds" ]; then
    echo "$submariner_crds" | xargs -r oc --context="$CLUSTER_1_NAME" delete crd --grace-period=0 2>/dev/null || true
  fi
) &

(
  echo "🗑️  Removing Submariner-related resources on cluster 2"
  oc --context="$CLUSTER_2_NAME" delete clusterrole -l app=submariner --grace-period=0 2>/dev/null || true
  oc --context="$CLUSTER_2_NAME" delete clusterrolebinding -l app=submariner --grace-period=0 2>/dev/null || true
  # Delete Submariner CRDs
  submariner_crds=$(oc --context="$CLUSTER_2_NAME" get crd 2>/dev/null | grep submariner | awk '{print $1}')
  if [ -n "$submariner_crds" ]; then
    echo "$submariner_crds" | xargs -r oc --context="$CLUSTER_2_NAME" delete crd --grace-period=0 2>/dev/null || true
  fi
) &

(
  echo "🗑️  Removing webhook configurations"
  oc --context="$CLUSTER_1_NAME" delete validatingwebhookconfiguration -l app=multicluster-operators-subscription --grace-period=0 2>/dev/null || true
  oc --context="$CLUSTER_1_NAME" delete mutatingwebhookconfiguration -l app=multicluster-operators-subscription --grace-period=0 2>/dev/null || true
) &

wait
echo "  ✅ Cluster-scoped resource cleanup completed"
echo ""

echo "================================================================"
echo "✅ ACM cleanup completed"
echo "================================================================"
echo ""

# Step 10: Final verification that all ACM namespaces are deleted
echo "Step 10: Final verification of namespace deletion..."
echo "-----------------------------------------------------"
echo "⏳ Waiting for all ACM/Submariner namespaces to be fully deleted..."

SECONDS=0
MAX_WAIT=120  # 2 minutes max (reduced from 4 since we're more aggressive)

while true; do
  # Check if any ACM-related namespaces still exist
  REMAINING_NS=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name 2>/dev/null | grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive)' | sed 's|namespace/||' || echo "")

  if [ -z "$REMAINING_NS" ]; then
    echo "  ✅ All ACM/Submariner-related namespaces fully deleted - ready for installation"
    break
  fi

  if [ $((SECONDS % 15)) -eq 0 ]; then
    echo "  ⏱️  Still waiting for namespaces to be deleted (${SECONDS}s elapsed):"
    print_list "$REMAINING_NS"
  fi

  sleep 3

  if [ $SECONDS -ge $MAX_WAIT ]; then
    echo "  ⚠️  WARNING: Some namespaces still exist after ${MAX_WAIT}s"
    echo "  Attempting final forceful cleanup..."

    for ns in $REMAINING_NS; do
      echo "    Force finalizing namespace: $ns"
      oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o json 2>/dev/null | \
        jq '.metadata.finalizers = []' | \
        oc --context="$CLUSTER_1_NAME" replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true &
    done
    wait

    sleep 10

    # Final check
    STILL_REMAINING=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name 2>/dev/null | grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive)' | sed 's|namespace/||' || echo "")
    if [ -n "$STILL_REMAINING" ]; then
      echo "  ❌ ERROR: The following namespaces still exist:"
      print_list "$STILL_REMAINING"
      echo "  Manual intervention may be required."
      exit 1
    fi
    break
  fi
done
echo ""

echo "================================================================"
echo "✅ System ready for fresh ACM and Submariner installation"
echo "================================================================"

#!/usr/bin/env bash

# Cleanup script for ACM (Advanced Cluster Management) and related resources
# This script ensures a completely clean state before installing ACM

set -euo pipefail

# Helper function to remove finalizers and force delete a resource (non-blocking)
force_delete_resource() {
  local context=$1
  local resource_type=$2
  local resource_name=$3
  local namespace=${4:-}

  local ns_flag=""
  if [ -n "$namespace" ]; then
    ns_flag="-n $namespace"
  fi

  # Remove finalizers first
  # shellcheck disable=SC2086
  oc --context "$context" patch "$resource_type" "$resource_name" $ns_flag \
    --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true

  # Delete without waiting (non-blocking)
  # shellcheck disable=SC2086
  oc --context "$context" delete "$resource_type" "$resource_name" $ns_flag \
    --grace-period=0 --wait=false 2>/dev/null || true
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

# Step 1: Delete all ManagedClusters (clean deletion with timeout, then force if needed)
echo "Step 1: Deleting all ManagedClusters..."
echo "----------------------------------------"
MANAGEDCLUSTER_TIMEOUT=600  # 10 minutes timeout for clean deletion

for cluster_name in "${CLUSTERS[@]}"; do
  if oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" >/dev/null 2>&1; then
    echo "🗑️  Deleting ManagedCluster: $cluster_name (waiting up to ${MANAGEDCLUSTER_TIMEOUT}s for clean deletion)"

    # Try clean deletion first with timeout
    if timeout "${MANAGEDCLUSTER_TIMEOUT}s" oc --context "$CLUSTER_1_NAME" delete managedcluster "$cluster_name" \
      --wait=true 2>&1 | grep -v "^$" || true; then
      echo "  ✅ ManagedCluster '$cluster_name' deleted cleanly"
    else
      # If timeout or failure, force deletion
      echo "  ⚠️  Clean deletion timed out or failed, forcing deletion of ManagedCluster: $cluster_name"
      oc --context "$CLUSTER_1_NAME" patch managedcluster "$cluster_name" \
        --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
      oc --context "$CLUSTER_1_NAME" delete managedcluster "$cluster_name" \
        --grace-period=0 --wait=false 2>/dev/null || true
      echo "  ✅ ManagedCluster '$cluster_name' force deletion initiated"
    fi
  else
    echo "  ℹ️  ManagedCluster '$cluster_name' not found - skipping"
  fi
done
echo ""

# Step 2: Delete MultiClusterHub (BEFORE deleting namespaces)
echo "Step 2: Deleting MultiClusterHub..."
echo "------------------------------------"
oc --context="$CLUSTER_1_NAME" delete clusterrole open-cluster-management:cluster-manager-admin 2>/dev/null || true

if oc --context="$CLUSTER_1_NAME" get multiclusterhub -n open-cluster-management >/dev/null 2>&1; then
  echo "🗑️  Deleting MultiClusterHub instances (waiting for clean deletion)..."
  for mch in $(oc --context="$CLUSTER_1_NAME" get multiclusterhub -n open-cluster-management -o name 2>/dev/null); do
    mch_name=$(echo "$mch" | cut -d'/' -f2)
    echo "  Deleting MultiClusterHub: $mch_name"
    # Delete WITHOUT removing finalizers - let MCH clean up its resources properly
    # Use --wait=true to wait synchronously for complete deletion
    oc --context="$CLUSTER_1_NAME" delete multiclusterhub "$mch_name" \
      -n open-cluster-management --wait=true --timeout=300s 2>&1 | grep -v "^$" || true
    echo "  ✅ MultiClusterHub '$mch_name' deleted successfully"
  done
  echo "  ✅ All MultiClusterHub instances deleted"
else
  echo "  ℹ️  MultiClusterHub not found - skipping"
fi
echo ""

# Step 3: Delete MultiClusterEngine (BEFORE deleting namespaces)
echo "Step 3: Deleting MultiClusterEngine..."
echo "---------------------------------------"
# MultiClusterEngine is cluster-scoped, not namespaced
# We MUST wait synchronously for MCE deletion as it manages critical resources
if oc --context="$CLUSTER_1_NAME" get multiclusterengine >/dev/null 2>&1; then
  echo "🗑️  Deleting MultiClusterEngine instances (waiting for clean deletion)..."
  for mce in $(oc --context="$CLUSTER_1_NAME" get multiclusterengine -o name 2>/dev/null); do
    mce_name=$(echo "$mce" | cut -d'/' -f2)
    echo "  Deleting cluster-scoped MultiClusterEngine: $mce_name"
    # Delete WITHOUT removing finalizers - let MCE clean up its resources properly
    # Use --wait=true to wait synchronously for complete deletion
    oc --context="$CLUSTER_1_NAME" delete multiclusterengine "$mce_name" \
      --wait=true --timeout=300s 2>&1 | grep -v "^$" || true
    echo "  ✅ MultiClusterEngine '$mce_name' deleted successfully"
  done
  echo "  ✅ All MultiClusterEngine instances deleted"
else
  echo "  ℹ️  MultiClusterEngine not found - skipping"
fi
echo ""

# Step 4: Clean up auto-import-secrets (ACM will recreate them)
echo "Step 4: Cleaning up auto-import-secrets..."
echo "-------------------------------------------"
for cluster_name in "${CLUSTERS[@]}"; do
  if oc --context="$CLUSTER_1_NAME" get namespace "$cluster_name" &>/dev/null; then
    echo "🗑️  Cleaning auto-import-secret for cluster: $cluster_name"
    oc --context="$CLUSTER_1_NAME" delete secret auto-import-secret -n "$cluster_name" 2>/dev/null || true
  fi
done
echo "  ✅ Auto-import-secrets cleaned"
echo ""

# Step 5: Clean up klusterlet and agent resources on managed clusters (parallel)
echo "Step 5: Cleaning up klusterlet and agent resources..."
echo "------------------------------------------------------"

# Function to clean agent namespaces on a cluster
cleanup_agent_namespaces() {
  local context=$1
  local cluster_label=$2

  for ns in open-cluster-management-agent open-cluster-management-agent-addon submariner-operator; do
    if oc --context "$context" get namespace "$ns" >/dev/null 2>&1; then
      echo "🗑️  Force deleting $ns on $cluster_label"
      oc --context "$context" patch namespace "$ns" --type='json' \
        -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
      oc --context "$context" delete namespace "$ns" --grace-period=0 --wait=false 2>/dev/null || true
    fi
  done

  # Delete all ACM-related namespaces with dynamic suffixes
  echo "🗑️  Cleaning ACM-related namespaces with dynamic names on $cluster_label"
  acm_dynamic_ns=$(oc --context "$context" get namespaces -o name 2>/dev/null | \
    grep -E 'namespace/(open-cluster-management-|multicluster-engine-|hive-)' | \
    sed 's|namespace/||' || echo "")

  if [ -n "$acm_dynamic_ns" ]; then
    for ns in $acm_dynamic_ns; do
      echo "   - Deleting: $ns"
      oc --context "$context" patch namespace "$ns" --type='json' \
        -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
      oc --context "$context" delete namespace "$ns" --grace-period=0 --wait=false 2>/dev/null || true
    done
  fi

  # Delete klusterlet CRs
  if oc --context "$context" get klusterlet >/dev/null 2>&1; then
    echo "🗑️  Deleting klusterlet CRs on $cluster_label"
    for kl in $(oc --context "$context" get klusterlet -o name 2>/dev/null); do
      oc --context "$context" patch "$kl" --type='json' \
        -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
      oc --context "$context" delete "$kl" --grace-period=0 --wait=false 2>/dev/null || true
    done
  fi
}

# Clean both clusters in parallel
cleanup_agent_namespaces "$CLUSTER_1_NAME" "cluster 1" &
cleanup_agent_namespaces "$CLUSTER_2_NAME" "cluster 2" &
wait
echo "  ✅ Agent namespace cleanup initiated on both clusters"
echo ""

# Step 6: Clean up cluster-specific and ACM/Submariner namespaces (parallel deletion)
echo "Step 6: Cleaning up ACM and Submariner namespaces on hub..."
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
    oc --context "$CLUSTER_1_NAME" patch namespace "$ns" --type='json' \
      -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
    oc --context "$CLUSTER_1_NAME" delete namespace "$ns" --grace-period=0 --wait=false 2>/dev/null || true
  fi
done
echo "  ✅ Namespace deletion initiated for all ACM/Submariner namespaces"
echo ""

# Step 7: Delete ManagedClusterSet and related resources (fast)
echo "Step 7: Deleting ManagedClusterSet..."
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

# Step 8: Delete ACM Operator subscriptions and CSVs (fast)
echo "Step 8: Deleting ACM Operator..."
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

# Step 9: Force delete remaining ACM-related namespaces
echo "Step 9: Force deleting remaining ACM-related namespaces..."
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
          oc --context="$CLUSTER_1_NAME" patch "$search" -n "$ns" --type='json' \
            -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
        done
      fi

      # Force delete namespace immediately (no waiting)
      oc --context="$CLUSTER_1_NAME" patch namespace "$ns" --type='json' \
        -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
      oc --context="$CLUSTER_1_NAME" delete namespace "$ns" --grace-period=0 --wait=false 2>/dev/null || true
    fi
  done
  wait  # Wait for all parallel operations
  echo "  ✅ Namespace deletion initiated for all ACM namespaces"
else
  echo "ℹ️  No ACM-related namespaces found"
fi
echo ""

# Step 10: Clean up ACM and Submariner cluster-scoped resources (parallel)
echo "Step 10: Cleaning up cluster-scoped resources..."
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

# Step 11: Final verification that all ACM namespaces are deleted
echo "Step 11: Final cleanup and verification..."
echo "-----------------------------------------------------"
echo "🗑️  Final cleanup of potentially recreated namespaces..."
# The local-cluster namespace may be recreated by ACM operator during deletion
# Delete it one last time to ensure it's gone
if oc --context="$CLUSTER_1_NAME" get namespace local-cluster >/dev/null 2>&1; then
  echo "  🗑️  Deleting recreated namespace: local-cluster"
  oc --context="$CLUSTER_1_NAME" patch namespace local-cluster \
    --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
  oc --context="$CLUSTER_1_NAME" delete namespace local-cluster \
    --grace-period=0 --wait=false 2>/dev/null || true
fi
echo ""

echo "⏳ Waiting for all ACM/Submariner namespaces to be fully deleted..."

elapsed=0
MAX_WAIT=240  # 4 minutes max

while true; do
  # Check if any ACM-related namespaces are still in Terminating state on CLUSTER_1 (hub)
  REMAINING_NS=$(oc --context="$CLUSTER_1_NAME" get namespaces --field-selector status.phase=Terminating -o name 2>/dev/null | \
    grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive|local-cluster)' | \
    sed 's|namespace/||' || echo "")

  # Check if any ACM-related namespaces are still in Terminating state on CLUSTER_2 (managed)
  REMAINING_NS_C2=$(oc --context="$CLUSTER_2_NAME" get namespaces --field-selector status.phase=Terminating -o name 2>/dev/null | \
    grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive)' | \
    sed 's|namespace/||' || echo "")

  if [ -z "$REMAINING_NS" ] && [ -z "$REMAINING_NS_C2" ]; then
    echo "  ✅ All ACM/Submariner-related namespaces fully deleted on both clusters - ready for installation"
    break
  fi

  if [ $((elapsed % 15)) -eq 0 ]; then
    echo "  ⏱️  Still waiting for namespaces to be deleted (${elapsed}s elapsed):"
    if [ -n "$REMAINING_NS" ]; then
      echo "    On cluster 1 (hub):"
      print_list "$REMAINING_NS"
    fi
    if [ -n "$REMAINING_NS_C2" ]; then
      echo "    On cluster 2 (managed):"
      print_list "$REMAINING_NS_C2"
    fi
  fi

  sleep 3
  elapsed=$((elapsed + 3))

  if [ $elapsed -ge $MAX_WAIT ]; then
    echo "  ⚠️  WARNING: Some namespaces still exist after ${MAX_WAIT}s"
    echo "  Attempting final forceful cleanup..."

    # Force cleanup on cluster 1
    if [ -n "$REMAINING_NS" ]; then
      for ns in $REMAINING_NS; do
        echo "    Force finalizing namespace on cluster 1: $ns"
        # Try multiple methods to remove finalizers
        oc --context="$CLUSTER_1_NAME" patch namespace "$ns" \
          --type='json' -p='[{"op": "replace", "path": "/spec/finalizers", "value":[]}]' 2>/dev/null || true
        oc --context="$CLUSTER_1_NAME" patch namespace "$ns" \
          --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value":[]}]' 2>/dev/null || true
        oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o json 2>/dev/null | \
          jq '.metadata.finalizers = [] | .spec.finalizers = []' | \
          oc --context="$CLUSTER_1_NAME" replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
      done
    fi

    # Force cleanup on cluster 2
    if [ -n "$REMAINING_NS_C2" ]; then
      for ns in $REMAINING_NS_C2; do
        echo "    Force finalizing namespace on cluster 2: $ns"
        # Try multiple methods to remove finalizers
        oc --context="$CLUSTER_2_NAME" patch namespace "$ns" \
          --type='json' -p='[{"op": "replace", "path": "/spec/finalizers", "value":[]}]' 2>/dev/null || true
        oc --context="$CLUSTER_2_NAME" patch namespace "$ns" \
          --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value":[]}]' 2>/dev/null || true
        oc --context="$CLUSTER_2_NAME" get namespace "$ns" -o json 2>/dev/null | \
          jq '.metadata.finalizers = [] | .spec.finalizers = []' | \
          oc --context="$CLUSTER_2_NAME" replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
      done
    fi

    echo "  ⏳ Waiting up to 5 minutes for finalizers to be processed..."

    # Wait up to 5 minutes (300s) checking every 10s
    force_wait=0
    force_max_wait=300

    while [ $force_wait -lt $force_max_wait ]; do
      sleep 10
      force_wait=$((force_wait + 10))

      # Check on both clusters
      STILL_REMAINING=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name 2>/dev/null | \
        grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive|local-cluster)' | \
        sed 's|namespace/||' || echo "")
      STILL_REMAINING_C2=$(oc --context="$CLUSTER_2_NAME" get namespaces -o name 2>/dev/null | \
        grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive)' | \
        sed 's|namespace/||' || echo "")

      # If all gone, exit early
      if [ -z "$STILL_REMAINING" ] && [ -z "$STILL_REMAINING_C2" ]; then
        echo "  ✅ All namespaces deleted after ${force_wait}s"
        break
      fi

      # Report every 30s
      if [ $((force_wait % 30)) -eq 0 ]; then
        echo "  ⏱️  Still waiting for finalizers... (${force_wait}s elapsed)"
      fi
    done

    # Final check on both clusters
    STILL_REMAINING=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name 2>/dev/null | \
      grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive|local-cluster)' | \
      sed 's|namespace/||' || echo "")
    STILL_REMAINING_C2=$(oc --context="$CLUSTER_2_NAME" get namespaces -o name 2>/dev/null | \
      grep -E 'namespace/(open-cluster-management|multicluster-engine|submariner|hive)' | \
      sed 's|namespace/||' || echo "")

    if [ -n "$STILL_REMAINING" ] || [ -n "$STILL_REMAINING_C2" ]; then
      echo "  ⚠️  WARNING: Some namespaces still exist after forceful cleanup:"
      if [ -n "$STILL_REMAINING" ]; then
        echo "    On cluster 1 (hub):"
        print_list "$STILL_REMAINING"

        # Check if namespaces are in Terminating state (acceptable for fresh install)
        echo "    Checking status of remaining namespaces..."
        for ns in $STILL_REMAINING; do
          status=$(oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
          deletion_ts=$(oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "None")
          echo "      - $ns: status=$status, deletionTimestamp=$deletion_ts"
        done
      fi
      if [ -n "$STILL_REMAINING_C2" ]; then
        echo "    On cluster 2 (managed):"
        print_list "$STILL_REMAINING_C2"

        # Check if namespaces are in Terminating state (acceptable for fresh install)
        echo "    Checking status of remaining namespaces..."
        for ns in $STILL_REMAINING_C2; do
          status=$(oc --context="$CLUSTER_2_NAME" get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
          deletion_ts=$(oc --context="$CLUSTER_2_NAME" get namespace "$ns" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "None")
          echo "      - $ns: status=$status, deletionTimestamp=$deletion_ts"
        done
      fi

      # Check if all namespaces are in Terminating state (which is acceptable)
      all_terminating=true
      for ns in $STILL_REMAINING; do
        status=$(oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Active")
        if [ "$status" != "Terminating" ]; then
          all_terminating=false
          break
        fi
      done

      for ns in $STILL_REMAINING_C2; do
        status=$(oc --context="$CLUSTER_2_NAME" get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Active")
        if [ "$status" != "Terminating" ]; then
          all_terminating=false
          break
        fi
      done

      if [ "$all_terminating" = true ]; then
        echo "  ✅ All remaining namespaces are in 'Terminating' state - safe to proceed"
        echo "     These will be cleaned up by Kubernetes eventually."
      else
        echo "  ❌ ERROR: Some namespaces are not in Terminating state."
        echo "     Manual intervention may be required."
        exit 1
      fi
    fi
    break
  fi
done
echo ""

echo "================================================================"
echo "✅ System ready for fresh ACM and Submariner installation"
echo "================================================================"

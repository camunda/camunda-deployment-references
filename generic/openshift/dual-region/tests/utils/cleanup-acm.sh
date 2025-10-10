#!/usr/bin/env bash

# Cleanup script for ACM (Advanced Cluster Management) and related resources
# This script ensures a completely clean state before installing ACM

set -euo pipefail

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

MANAGEDCLUSTER_TIMEOUT=60  # Reduced timeout for ManagedCluster deletion
CLUSTERS=("local-cluster" "$CLUSTER_2_NAME")

# Step 1: Delete all ManagedClusters (aggressive mode)
echo "Step 1: Deleting all ManagedClusters..."
echo "----------------------------------------"
for cluster_name in "${CLUSTERS[@]}"; do
  echo "🗑️  Deleting ManagedCluster: $cluster_name"

  if oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" >/dev/null 2>&1; then

    # Immediately remove finalizers (don't wait for graceful deletion in cleanup scenario)
    echo "  Removing finalizers immediately..."
    oc --context "$CLUSTER_1_NAME" patch managedcluster "$cluster_name" \
      --type='merge' -p '{"metadata":{"finalizers":[]}}' || true

    # Now delete with short timeout
    echo "  Deleting resource..."
    oc --context "$CLUSTER_1_NAME" delete managedcluster "$cluster_name" \
      --timeout=30s --grace-period=0 2>/dev/null || true

    # Verify deletion (short wait)
    echo "⏳ Verifying deletion of '$cluster_name'..."
    SECONDS=0
    while oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" >/dev/null 2>&1; do
      if [ $((SECONDS % 10)) -eq 0 ]; then
        echo "  Still waiting... (${SECONDS}s elapsed)"
      fi
      sleep 2

      if [ "$SECONDS" -ge "$MANAGEDCLUSTER_TIMEOUT" ]; then
        echo "  ⚠️  ManagedCluster still present after $MANAGEDCLUSTER_TIMEOUT seconds"
        echo "  Forcing final removal..."
        oc --context "$CLUSTER_1_NAME" patch managedcluster "$cluster_name" \
          --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
        oc --context "$CLUSTER_1_NAME" delete managedcluster "$cluster_name" \
          --grace-period=0 --force 2>/dev/null || true
        sleep 5
        break
      fi
    done

    if ! oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" >/dev/null 2>&1; then
      echo "  ✅ ManagedCluster '$cluster_name' deleted"
    else
      echo "  ⚠️  ManagedCluster '$cluster_name' still exists - continuing anyway"
    fi
  else
    echo "  ℹ️  ManagedCluster '$cluster_name' not found - skipping"
  fi
  echo ""
done

# Step 2: Clean up cluster-specific namespaces on hub
echo "Step 2: Cleaning up cluster namespaces on hub..."
echo "-------------------------------------------------"
for cluster_name in "${CLUSTERS[@]}"; do
  if oc --context "$CLUSTER_1_NAME" get namespace "$cluster_name" >/dev/null 2>&1; then
    echo "🗑️  Deleting namespace: $cluster_name"
    oc --context "$CLUSTER_1_NAME" delete namespace "$cluster_name" --timeout=60s || {
      echo "  ⚠️  Normal deletion failed, forcing..."
      # Remove finalizers from all resources in the namespace
      oc --context "$CLUSTER_1_NAME" patch namespace "$cluster_name" --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
    }
  fi
done

# Also clean up ACM global namespaces
echo "Cleaning up additional ACM namespaces..."
for ns in open-cluster-management-global-set open-cluster-management-hub; do
  if oc --context "$CLUSTER_1_NAME" get namespace "$ns" >/dev/null 2>&1; then
    echo "🗑️  Deleting namespace: $ns"
    oc --context "$CLUSTER_1_NAME" delete namespace "$ns" --timeout=60s || {
      echo "  ⚠️  Normal deletion failed, forcing..."
      oc --context "$CLUSTER_1_NAME" patch namespace "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
    }
  fi
done
echo ""

# Step 3: Clean up klusterlet resources on managed clusters
echo "Step 3: Cleaning up klusterlet resources on managed clusters..."
echo "----------------------------------------------------------------"

# Clean cluster 1 (hub, also a managed cluster as local-cluster)
if oc --context "$CLUSTER_1_NAME" get namespace open-cluster-management-agent >/dev/null 2>&1; then
  echo "🗑️  Cleaning klusterlet on cluster 1 (hub/local-cluster)"
  oc --context "$CLUSTER_1_NAME" -n open-cluster-management-agent delete all --all --timeout=30s || true
  oc --context "$CLUSTER_1_NAME" delete namespace open-cluster-management-agent --timeout=60s || {
    oc --context "$CLUSTER_1_NAME" patch namespace open-cluster-management-agent --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
  }
fi

if oc --context "$CLUSTER_1_NAME" get namespace open-cluster-management-agent-addon >/dev/null 2>&1; then
  echo "🗑️  Cleaning klusterlet addon namespace on cluster 1"
  oc --context "$CLUSTER_1_NAME" delete namespace open-cluster-management-agent-addon --timeout=60s || {
    oc --context "$CLUSTER_1_NAME" patch namespace open-cluster-management-agent-addon --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
  }
fi

# Clean cluster 2
if oc --context "$CLUSTER_2_NAME" get namespace open-cluster-management-agent >/dev/null 2>&1; then
  echo "🗑️  Cleaning klusterlet on cluster 2"
  oc --context "$CLUSTER_2_NAME" -n open-cluster-management-agent delete all --all --timeout=30s || true
  oc --context "$CLUSTER_2_NAME" delete namespace open-cluster-management-agent --timeout=60s || {
    oc --context "$CLUSTER_2_NAME" patch namespace open-cluster-management-agent --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
  }
fi

if oc --context "$CLUSTER_2_NAME" get namespace open-cluster-management-agent-addon >/dev/null 2>&1; then
  echo "🗑️  Cleaning klusterlet addon namespace on cluster 2"
  oc --context "$CLUSTER_2_NAME" delete namespace open-cluster-management-agent-addon --timeout=60s || {
    oc --context "$CLUSTER_2_NAME" patch namespace open-cluster-management-agent-addon --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
  }
fi

# Delete klusterlet CRs if they exist
if oc --context "$CLUSTER_1_NAME" get klusterlet >/dev/null 2>&1; then
  echo "🗑️  Deleting klusterlet CRs on cluster 1"
  oc --context "$CLUSTER_1_NAME" delete klusterlet --all --timeout=30s || {
    for kl in $(oc --context "$CLUSTER_1_NAME" get klusterlet -o name); do
      oc --context "$CLUSTER_1_NAME" patch "$kl" --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
    done
  }
fi

if oc --context "$CLUSTER_2_NAME" get klusterlet >/dev/null 2>&1; then
  echo "🗑️  Deleting klusterlet CRs on cluster 2"
  oc --context "$CLUSTER_2_NAME" delete klusterlet --all --timeout=30s || {
    for kl in $(oc --context "$CLUSTER_2_NAME" get klusterlet -o name); do
      oc --context "$CLUSTER_2_NAME" patch "$kl" --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
    done
  }
fi
echo ""

# Step 4: Delete ManagedClusterSet and related resources
echo "Step 4: Deleting ManagedClusterSet..."
echo "-------------------------------------"
if oc --context="$CLUSTER_1_NAME" get managedclusterset camunda-zeebe >/dev/null 2>&1; then
  echo "🗑️  Deleting ManagedClusterSet: camunda-zeebe"
  oc --context="$CLUSTER_1_NAME" delete -f ./generic/openshift/dual-region/procedure/acm/managed-cluster-set.yml --timeout=60s || {
    oc --context="$CLUSTER_1_NAME" patch managedclusterset camunda-zeebe --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
  }
fi

if oc --context="$CLUSTER_1_NAME" get managedclustersetbinding camunda-zeebe \
    -n open-cluster-management >/dev/null 2>&1; then
  echo "🗑️  Deleting ManagedClusterSetBinding: camunda-zeebe"
  oc --context="$CLUSTER_1_NAME" delete managedclustersetbinding camunda-zeebe \
    -n open-cluster-management --timeout=60s || {
    oc --context="$CLUSTER_1_NAME" patch managedclustersetbinding camunda-zeebe \
      -n open-cluster-management --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
  }
fi
echo ""

# Step 5: Delete MultiClusterHub (aggressive cleanup)
echo "Step 5: Deleting MultiClusterHub..."
echo "------------------------------------"
if oc --context="$CLUSTER_1_NAME" get clusterrole open-cluster-management:cluster-manager-admin >/dev/null 2>&1; then
  echo "🗑️  Deleting cluster role: open-cluster-management:cluster-manager-admin"
  oc --context="$CLUSTER_1_NAME" delete clusterrole open-cluster-management:cluster-manager-admin || true
fi

if oc --context="$CLUSTER_1_NAME" get crd multiclusterhubs.operator.open-cluster-management.io >/dev/null 2>&1; then
  # Check if MultiClusterHub exists
  if oc --context="$CLUSTER_1_NAME" get multiclusterhub -n open-cluster-management >/dev/null 2>&1; then
    echo "🗑️  MultiClusterHub found - forcing immediate deletion"

    # Immediate finalizer removal (don't wait for graceful deletion)
    echo "  Removing finalizers immediately..."
    for mch in $(oc --context="$CLUSTER_1_NAME" get multiclusterhub -n open-cluster-management -o name 2>/dev/null); do
      oc --context="$CLUSTER_1_NAME" patch "$mch" -n open-cluster-management --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
    done

    # Force delete with zero grace period
    echo "  Force deleting resource..."
    oc --context="$CLUSTER_1_NAME" delete multiclusterhub --all -n open-cluster-management --grace-period=0 --force 2>/dev/null || true

    # Verify deletion (short timeout since we forced it)
    echo "⏳ Verifying deletion..."
    SECONDS=0
    while oc --context="$CLUSTER_1_NAME" get multiclusterhub -n open-cluster-management >/dev/null 2>&1; do
      if [ $((SECONDS % 10)) -eq 0 ]; then
        echo "  Still waiting for deletion... (${SECONDS}s elapsed)"
      fi
      sleep 2

      if [ $SECONDS -ge 60 ]; then
        echo "  ⚠️  MultiClusterHub still present after force delete - will clean namespace"
        break
      fi
    done
    echo "  ✅ MultiClusterHub deletion complete"
  else
    echo "  ℹ️  MultiClusterHub not found - already deleted"
  fi
else
  echo "  ℹ️  MultiClusterHub CRD not found - skipping"
fi
echo ""

# Step 6: Delete ACM Operator Subscription and CSV
echo "Step 6: Deleting ACM Operator..."
echo "---------------------------------"
if oc --context="$CLUSTER_1_NAME" get subscription advanced-cluster-management -n open-cluster-management >/dev/null 2>&1; then
  echo "🗑️  Deleting ACM subscription"
  oc --context="$CLUSTER_1_NAME" delete subscription advanced-cluster-management -n open-cluster-management --timeout=30s || true
fi

# Delete ClusterServiceVersion (CSV) for ACM
if oc --context="$CLUSTER_1_NAME" get csv -n open-cluster-management \
    | grep -q advanced-cluster-management; then
  echo "🗑️  Deleting ACM ClusterServiceVersion"
  oc --context="$CLUSTER_1_NAME" delete csv -n open-cluster-management \
    -l operators.coreos.com/advanced-cluster-management.open-cluster-management= \
    --timeout=30s || true
fi
echo ""

# Step 7: Delete MultiClusterEngine (aggressive cleanup)
echo "Step 7: Deleting MultiClusterEngine..."
echo "---------------------------------------"
if oc --context="$CLUSTER_1_NAME" get crd multiclusterengines.multicluster.openshift.io >/dev/null 2>&1; then
  # Check if MultiClusterEngine exists
  if oc --context="$CLUSTER_1_NAME" get multiclusterengine -n open-cluster-management >/dev/null 2>&1; then
    echo "🗑️  MultiClusterEngine found - forcing immediate deletion"

    # Immediate finalizer removal
    echo "  Removing finalizers immediately..."
    for mce in $(oc --context="$CLUSTER_1_NAME" get multiclusterengine -n open-cluster-management -o name 2>/dev/null); do
      oc --context="$CLUSTER_1_NAME" patch "$mce" -n open-cluster-management --type='merge' -p '{"metadata":{"finalizers":[]}}' || true
    done

    # Force delete with zero grace period
    echo "  Force deleting resource..."
    oc --context="$CLUSTER_1_NAME" delete multiclusterengine --all -n open-cluster-management --grace-period=0 --force 2>/dev/null || true

    # Verify deletion (short timeout)
    echo "⏳ Verifying deletion..."
    SECONDS=0
    while oc --context="$CLUSTER_1_NAME" get multiclusterengine -n open-cluster-management >/dev/null 2>&1; do
      if [ $((SECONDS % 10)) -eq 0 ]; then
        echo "  Still waiting for deletion... (${SECONDS}s elapsed)"
      fi
      sleep 2

      if [ "$SECONDS" -ge 60 ]; then
        echo "  ⚠️  MultiClusterEngine still present after force delete - will clean namespace"
        break
      fi
    done
    echo "  ✅ MultiClusterEngine deletion complete"
  else
    echo "  ℹ️  MultiClusterEngine not found - already deleted"
  fi
else
  echo "  ℹ️  MultiClusterEngine CRD not found - skipping"
fi
echo ""

# Step 8: Delete all ACM-related namespaces (with thorough verification)
echo "Step 8: Deleting all ACM-related namespaces..."
echo "----------------------------------------------------"

# Get all ACM-related namespaces
ACM_NAMESPACES=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name | grep -E 'namespace/(open-cluster-management|multicluster-engine)' | sed 's|namespace/||' || echo "")

if [ -n "$ACM_NAMESPACES" ]; then
  echo "Found ACM-related namespaces:"
  while IFS= read -r ns; do
    echo "  - $ns"
  done <<< "$ACM_NAMESPACES"
  echo ""

  for ns in $ACM_NAMESPACES; do
    echo "🗑️  Processing namespace: $ns"

    if oc --context="$CLUSTER_1_NAME" get namespace "$ns" >/dev/null 2>&1; then
      # Remove finalizers from search resources that can block namespace deletion
      if [ "$ns" = "open-cluster-management" ]; then
        echo "  Removing finalizers from search resources..."
        if oc --context="$CLUSTER_1_NAME" get searches.search.open-cluster-management.io -n "$ns" >/dev/null 2>&1; then
          for search in $(oc --context="$CLUSTER_1_NAME" get searches.search.open-cluster-management.io -n "$ns" -o name 2>/dev/null); do
            echo "    Patching $search"
            oc --context="$CLUSTER_1_NAME" patch "$search" -n "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
          done
        fi
      fi

      # Delete all resources in the namespace
      echo "  Deleting all resources in namespace $ns..."
      oc --context="$CLUSTER_1_NAME" delete all --all -n "$ns" --timeout=30s 2>/dev/null || true

      # Try graceful deletion
      echo "  Deleting namespace $ns..."
      oc --context="$CLUSTER_1_NAME" delete namespace "$ns" --timeout=60s || {
        echo "  ⚠️  Graceful deletion timed out, investigating..."

        # Check namespace status
        ns_status=$(oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        echo "  Namespace status: $ns_status"

        if [ "$ns_status" = "Terminating" ]; then
          echo "  Namespace stuck in Terminating state, removing finalizers..."

          # Remove finalizers from all resources in the namespace
          echo "  Removing finalizers from all pods..."
          for pod in $(oc --context="$CLUSTER_1_NAME" get pods -n "$ns" -o name 2>/dev/null); do
            oc --context="$CLUSTER_1_NAME" patch "$pod" -n "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
          done

          echo "  Removing finalizers from all deployments..."
          for deploy in $(oc --context="$CLUSTER_1_NAME" get deployments -n "$ns" -o name 2>/dev/null); do
            oc --context="$CLUSTER_1_NAME" patch "$deploy" -n "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
          done

          # Finally remove namespace finalizers
          echo "  Removing namespace finalizers..."
          oc --context="$CLUSTER_1_NAME" patch namespace "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' || true

          sleep 5
        fi
      }

      # Wait for namespace to be completely gone (shorter timeout per namespace)
      echo "  ⏳ Waiting for namespace $ns to be deleted..."
      SECONDS=0
      while oc --context="$CLUSTER_1_NAME" get namespace "$ns" >/dev/null 2>&1; do
        if [ $((SECONDS % 10)) -eq 0 ]; then
          ns_phase=$(oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Deleted")
          echo "    Still waiting... namespace phase: $ns_phase (${SECONDS}s elapsed)"
        fi
        sleep 3

        if [ $SECONDS -ge 90 ]; then
          echo "    ⛔ Timeout after 90s - forcing final removal"
          # Last resort: remove all finalizers from namespace
          oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o json 2>/dev/null | \
            jq '.metadata.finalizers = []' | \
            oc --context="$CLUSTER_1_NAME" replace --raw "/api/v1/namespaces/$ns/finalize" -f - || true
          sleep 10
          break
        fi
      done

      # Verification per namespace
      if ! oc --context="$CLUSTER_1_NAME" get namespace "$ns" >/dev/null 2>&1; then
        echo "  ✅ Namespace $ns completely deleted"
      else
        echo "  ⚠️  WARNING: Namespace $ns still exists after cleanup attempts!"
      fi
      echo ""
    fi
  done
else
  echo "ℹ️  No ACM-related namespaces found"
fi
echo ""

# Step 9: Clean up remaining ACM CRDs and cluster-scoped resources
echo "Step 9: Cleaning up ACM CRDs and cluster resources..."
echo "------------------------------------------------------"
echo "🗑️  Removing ACM-related ClusterRoles and ClusterRoleBindings"
oc --context="$CLUSTER_1_NAME" delete clusterrole -l open-cluster-management.io/aggregate-to-work= --timeout=30s 2>/dev/null || true
oc --context="$CLUSTER_1_NAME" delete clusterrolebinding -l open-cluster-management.io/aggregate-to-work= --timeout=30s 2>/dev/null || true

echo "🗑️  Removing webhook configurations"
oc --context="$CLUSTER_1_NAME" delete validatingwebhookconfiguration -l app=multicluster-operators-subscription --timeout=30s 2>/dev/null || true
oc --context="$CLUSTER_1_NAME" delete mutatingwebhookconfiguration -l app=multicluster-operators-subscription --timeout=30s 2>/dev/null || true
echo ""

echo "================================================================"
echo "✅ ACM cleanup completed"
echo "================================================================"
echo ""

# Step 10: Final verification that all ACM namespaces are deleted
echo "Step 10: Final verification of namespace deletion..."
echo "-----------------------------------------------------"
echo "⏳ Ensuring all ACM-related namespaces are fully deleted..."

SECONDS=0
MAX_WAIT=240  # 4 minutes max

while true; do
  # Check if any ACM-related namespaces still exist
  REMAINING_NS=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name 2>/dev/null | grep -E 'namespace/(open-cluster-management|multicluster-engine)' | sed 's|namespace/||' || echo "")

  if [ -z "$REMAINING_NS" ]; then
    echo "  ✅ All ACM-related namespaces fully deleted - ready for ACM installation"
    break
  fi

  if [ $((SECONDS % 10)) -eq 0 ]; then
    echo "  ⏱️  Still waiting for namespaces to be deleted (${SECONDS}s elapsed):"
    while IFS= read -r ns; do
      echo "      - $ns"
    done <<< "$REMAINING_NS"
  fi

  sleep 3

  if [ $SECONDS -ge $MAX_WAIT ]; then
    echo "  ⚠️  WARNING: Some namespaces still exist after ${MAX_WAIT}s"
    echo "  Attempting final cleanup on remaining namespaces..."

    for ns in $REMAINING_NS; do
      echo "    Force removing finalizers from $ns..."
      oc --context="$CLUSTER_1_NAME" get namespace "$ns" -o json 2>/dev/null | \
        jq '.metadata.finalizers = []' | \
        oc --context="$CLUSTER_1_NAME" replace --raw "/api/v1/namespaces/$ns/finalize" -f - || true
    done

    sleep 10

    # Final check
    STILL_REMAINING=$(oc --context="$CLUSTER_1_NAME" get namespaces -o name 2>/dev/null | grep -E 'namespace/(open-cluster-management|multicluster-engine)' | sed 's|namespace/||' || echo "")
    if [ -n "$STILL_REMAINING" ]; then
      echo "  ❌ ERROR: The following namespaces still exist:"
      while IFS= read -r ns; do
        echo "      - $ns"
      done <<< "$REMAINING_NS"
      echo "  This may cause ACM installation to fail. Manual intervention may be required."
      exit 1
    fi
    break
  fi
done
echo ""

echo "================================================================"
echo "✅ System ready for fresh ACM installation"
echo "================================================================"

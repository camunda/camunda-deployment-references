#!/bin/bash

set -euo pipefail

echo "🔍 Pre-flight checks for Submariner installation"
echo "================================================="
echo ""

EXIT_CODE=0

# Check 1: ManagedClusters status
echo "1️⃣  Checking ManagedClusters status..."
if ! oc --context "$CLUSTER_1_NAME" get managedclusters &>/dev/null; then
    echo "❌ Cannot access ManagedClusters"
    EXIT_CODE=1
else
    STATUS=$(oc --context "$CLUSTER_1_NAME" get managedclusters)
    echo "$STATUS"

    if echo "$STATUS" | awk 'NR>1 {if ($2=="true" && $4=="True" && $5=="True") next; else exit 1}'; then
        echo "✅ All ManagedClusters are healthy"
    else
        echo "❌ Some ManagedClusters are not healthy!"
        echo "   Please fix cluster import issues before installing Submariner."
        EXIT_CODE=1
    fi
fi
echo ""

# Check 2: ManagedClusterSet
echo "2️⃣  Checking ManagedClusterSet..."
if ! oc --context "$CLUSTER_1_NAME" get managedclusterset oc-clusters &>/dev/null; then
    echo "❌ ManagedClusterSet 'oc-clusters' not found"
    EXIT_CODE=1
else
    echo "✅ ManagedClusterSet 'oc-clusters' exists"
    oc --context "$CLUSTER_1_NAME" get managedclusterset oc-clusters
fi
echo ""

# Check 3: MultiClusterHub status
echo "3️⃣  Checking MultiClusterHub status..."
MCH_STATUS=$(oc --context "$CLUSTER_1_NAME" get mch -n open-cluster-management -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$MCH_STATUS" = "Running" ]; then
    echo "✅ MultiClusterHub is Running"
else
    echo "❌ MultiClusterHub is not Running (status: $MCH_STATUS)"
    EXIT_CODE=1
fi
echo ""

# Check 4: Check if submariner-broker namespace exists
echo "4️⃣  Checking submariner broker namespace..."
if oc --context "$CLUSTER_1_NAME" get namespace oc-clusters-broker &>/dev/null; then
    echo "⚠️  Namespace 'oc-clusters-broker' already exists"
    echo "   This may indicate a previous installation. Consider cleaning up first."
else
    echo "✅ Namespace 'oc-clusters-broker' does not exist (clean state)"
fi
echo ""

# Check 5: Gateway nodes labeled
echo "5️⃣  Checking if gateway nodes are labeled..."
echo "   Cluster 1 (local-cluster):"
LABELED_NODES_1=$(oc --context "$CLUSTER_1_NAME" get nodes -l submariner.io/gateway=true -o name 2>/dev/null | wc -l)
if [ "$LABELED_NODES_1" -gt 0 ]; then
    echo "   ✅ $LABELED_NODES_1 node(s) labeled"
    oc --context "$CLUSTER_1_NAME" get nodes -l submariner.io/gateway=true
else
    echo "   ⚠️  No nodes labeled with submariner.io/gateway=true"
    echo "   This is OK - labels will be applied by label-nodes-brokers.sh"
fi

echo ""
echo "   Cluster 2 ($CLUSTER_2_NAME):"
LABELED_NODES_2=$(oc --context "$CLUSTER_2_NAME" get nodes -l submariner.io/gateway=true -o name 2>/dev/null | wc -l)
if [ "$LABELED_NODES_2" -gt 0 ]; then
    echo "   ✅ $LABELED_NODES_2 node(s) labeled"
    oc --context "$CLUSTER_2_NAME" get nodes -l submariner.io/gateway=true
else
    echo "   ⚠️  No nodes labeled with submariner.io/gateway=true"
    echo "   This is OK - labels will be applied by label-nodes-brokers.sh"
fi
echo ""

# Check 6: Network prerequisites
echo "6️⃣  Checking network prerequisites..."
echo "   Verifying cluster connectivity..."

# Check if we can reach both cluster APIs
if oc --context "$CLUSTER_1_NAME" cluster-info &>/dev/null; then
    echo "   ✅ Can access Cluster 1 API"
else
    echo "   ❌ Cannot access Cluster 1 API"
    EXIT_CODE=1
fi

if oc --context "$CLUSTER_2_NAME" cluster-info &>/dev/null; then
    echo "   ✅ Can access Cluster 2 API"
else
    echo "   ❌ Cannot access Cluster 2 API"
    EXIT_CODE=1
fi
echo ""

# Check 7: Check for existing Submariner installations
echo "7️⃣  Checking for existing Submariner installations..."
if oc --context "$CLUSTER_1_NAME" get managedclusteraddon -A | grep -q submariner 2>/dev/null; then
    echo "   ⚠️  Submariner addons already exist!"
    oc --context "$CLUSTER_1_NAME" get managedclusteraddon -A | grep submariner
    echo ""
    echo "   Consider cleaning up existing installation first."
else
    echo "   ✅ No existing Submariner installations found (clean state)"
fi
echo ""

# Check 8: Verify required operators are installed
echo "8️⃣  Checking required operators..."
if oc --context "$CLUSTER_1_NAME" get csv -n open-cluster-management | grep -q "advanced-cluster-management"; then
    echo "   ✅ ACM operator is installed"
else
    echo "   ❌ ACM operator not found"
    EXIT_CODE=1
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 PRE-FLIGHT CHECK SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ All pre-flight checks passed!"
    echo ""
    echo "You can now proceed with Submariner installation:"
    echo "  1. ./list-nodes-brokers.sh"
    echo "  2. ./label-nodes-brokers.sh"
    echo "  3. ./install-submariner.sh"
    echo "  4. ./verify-submariner.sh"
else
    echo "❌ Some pre-flight checks failed!"
    echo ""
    echo "Please resolve the issues above before proceeding with Submariner installation."
    echo ""
    echo "Common fixes:"
    echo "  - Wait for ManagedClusters to become healthy: ./verify-managed-cluster-set.sh"
    echo "  - Debug cluster issues: ./debug-managed-cluster.sh <cluster-name>"
    echo "  - Verify MultiClusterHub: ./verify-multi-cluster-hub.sh"
fi
echo ""

exit $EXIT_CODE

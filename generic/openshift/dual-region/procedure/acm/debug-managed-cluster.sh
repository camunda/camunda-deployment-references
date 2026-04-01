#!/bin/bash
set -euo pipefail

# Debug script for troubleshooting ManagedCluster issues
# Usage: ./debug-managed-cluster.sh <cluster-name>

set -euo pipefail

CLUSTER_NAME="${1:-}"

if [ -z "$CLUSTER_NAME" ]; then
    echo "Usage: $0 <cluster-name>"
    echo ""
    echo "Available clusters:"
    # shellcheck disable=SC2153  # CLUSTER_0 is set as an environment variable
    oc --context "$CLUSTER_0" get managedclusters -o name
    exit 1
fi

echo "🔍 Debugging ManagedCluster: $CLUSTER_NAME"
echo "============================================="
echo ""

# 1. Check ManagedCluster resource
echo "1️⃣  ManagedCluster Status:"
echo "---"
oc --context "$CLUSTER_0" get managedcluster "$CLUSTER_NAME" -o yaml
echo ""

# 2. Check ManagedCluster conditions
echo "2️⃣  ManagedCluster Conditions:"
echo "---"
oc --context "$CLUSTER_0" get managedcluster "$CLUSTER_NAME" -o jsonpath='{.status.conditions[*]}' | jq -r '.[] | "Type: \(.type) | Status: \(.status) | Reason: \(.reason // "N/A") | Message: \(.message // "N/A")"' || echo "No conditions found or jq not available"
echo ""

# 3. Check auto-import-secret
echo "3️⃣  Auto-Import Secret:"
echo "---"
if oc --context "$CLUSTER_0" get secret auto-import-secret -n "$CLUSTER_NAME" &>/dev/null; then
    echo "✅ Secret exists"
    echo "Server: $(oc --context "$CLUSTER_0" get secret auto-import-secret -n "$CLUSTER_NAME" -o jsonpath='{.data.server}' | base64 -d)"
    TOKEN=$(oc --context "$CLUSTER_0" get secret auto-import-secret -n "$CLUSTER_NAME" -o jsonpath='{.data.token}' | base64 -d)
    if [ -n "$TOKEN" ]; then
        echo "Token: [REDACTED] (length: ${#TOKEN} chars)"
    else
        echo "❌ Token is empty!"
    fi
    echo "autoImportRetry: $(oc --context "$CLUSTER_0" get secret auto-import-secret -n "$CLUSTER_NAME" -o jsonpath='{.data.autoImportRetry}' | base64 -d)"
else
    echo "❌ auto-import-secret NOT FOUND in namespace $CLUSTER_NAME"
fi
echo ""

# 4. Check namespace
echo "4️⃣  Namespace Status:"
echo "---"
if oc --context "$CLUSTER_0" get namespace "$CLUSTER_NAME" &>/dev/null; then
    echo "✅ Namespace $CLUSTER_NAME exists"
    oc --context "$CLUSTER_0" get namespace "$CLUSTER_NAME"
else
    echo "❌ Namespace $CLUSTER_NAME NOT FOUND"
fi
echo ""

# 5. Check pods in cluster namespace
echo "5️⃣  Pods in namespace $CLUSTER_NAME:"
echo "---"
if oc --context "$CLUSTER_0" get namespace "$CLUSTER_NAME" &>/dev/null; then
    oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get pods
    echo ""
    echo "Pod details:"
    for pod in $(oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get pods -o name 2>/dev/null); do
        echo "  $pod:"
        oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" describe "$pod" | grep -A 5 "Events:" || true
    done
else
    echo "Namespace not found, skipping pod check"
fi
echo ""

# 6. Check ManifestWork
echo "6️⃣  ManifestWork Status:"
echo "---"
if oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get manifestwork &>/dev/null; then
    oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get manifestwork
    echo ""
    echo "ManifestWork details:"
    for mw in $(oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get manifestwork -o name); do
        echo "  $mw:"
        oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get "$mw" -o jsonpath='{.status.conditions[*]}' | jq -r '. | "Status: \(.type) = \(.status) | Reason: \(.reason // "N/A")"' 2>/dev/null || echo "    No conditions or jq unavailable"
    done
else
    echo "No ManifestWork found"
fi
echo ""

# 7. Check KlusterletAddonConfig
echo "7️⃣  KlusterletAddonConfig:"
echo "---"
if oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get klusterletaddonconfig &>/dev/null; then
    oc --context "$CLUSTER_0" -n "$CLUSTER_NAME" get klusterletaddonconfig -o yaml
else
    echo "No KlusterletAddonConfig found"
fi
echo ""

# 8. Check open-cluster-management-agent namespace on hub
echo "8️⃣  Open Cluster Management Agent (Hub):"
echo "---"
if oc --context "$CLUSTER_0" get namespace "open-cluster-management-agent" &>/dev/null; then
    oc --context "$CLUSTER_0" -n "open-cluster-management-agent" get pods
else
    echo "Namespace open-cluster-management-agent not found"
fi
echo ""

# 9. Check import controller logs
echo "9️⃣  Import Controller Logs:"
echo "---"
for pod in $(oc --context "$CLUSTER_0" -n open-cluster-management get pods -l app=managedcluster-import-controller-v2 -o name 2>/dev/null); do
    echo "Logs from $pod (last 50 lines):"
    oc --context "$CLUSTER_0" -n open-cluster-management logs "$pod" --tail=50 | grep -i "$CLUSTER_NAME" || echo "No logs mentioning $CLUSTER_NAME"
done
echo ""

# 10. Suggested fixes
echo "🔧 Suggested Fixes:"
echo "---"
echo "If the cluster is stuck in Unknown state, try:"
echo ""
echo "1. Force reconciliation:"
echo "   oc --context \"\$CLUSTER_0\" annotate managedcluster \"$CLUSTER_NAME\" import.open-cluster-management.io/retry=\"\$(date +%s)\" --overwrite"
echo ""
echo "2. Check if the token is expired and recreate the secret:"
echo "   # Get new token from target cluster"
echo "   NEW_TOKEN=\$(oc --context \"\$CLUSTER_1\" whoami -t)"
echo "   CLUSTER_API=\$(oc config view --minify --context \"\$CLUSTER_1\" --raw -o json | jq -r '.clusters[].cluster.server')"
echo "   # Delete and recreate the secret"
echo "   oc --context \"\$CLUSTER_0\" delete secret auto-import-secret -n \"$CLUSTER_NAME\""
echo "   oc --context \"\$CLUSTER_0\" create secret generic auto-import-secret -n \"$CLUSTER_NAME\" \\"
echo "     --from-literal=autoImportRetry=5 \\"
echo "     --from-literal=token=\"\$NEW_TOKEN\" \\"
echo "     --from-literal=server=\"\$CLUSTER_API\""
echo ""
echo "3. Delete and reimport the cluster:"
echo "   oc --context \"\$CLUSTER_0\" delete managedcluster \"$CLUSTER_NAME\""
echo "   # Then run initiate-cluster-set.sh again"
echo ""
echo "4. Check network connectivity between hub and managed cluster"
echo ""
echo "5. Verify RBAC permissions on the managed cluster for the service account token"
echo ""

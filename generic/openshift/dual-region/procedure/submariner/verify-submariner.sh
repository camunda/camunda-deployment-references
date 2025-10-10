#!/bin/bash

# TODO: once it works, revert this as it's exposed to doc


# Timeout after 15 minutes (900 seconds)
TIMEOUT_SECONDS=900
SECONDS=0

echo "🐠 Verifying Submariner installation..."
echo "========================================"
echo ""

while true; do
    echo "⏳ Checking Submariner addon status... (${SECONDS}s / ${TIMEOUT_SECONDS}s)"

    # Get submariner addon status
    STATUS=$(oc --context "$CLUSTER_1_NAME" get managedclusteraddon -A 2>/dev/null | grep 'submariner' || echo "")

    if [ -z "$STATUS" ]; then
        echo "⚠️  No Submariner addons found yet..."
    else
        echo ""
        echo "Current status:"
        oc --context "$CLUSTER_1_NAME" get managedclusteraddon -A | grep -E 'NAMESPACE|submariner'
        echo ""

        # Check if all addons are healthy (Available=True, Degraded=False or empty, Progressing=False or empty)
        if echo "$STATUS" | awk '{if ($3=="True" && ($4=="False" || $4=="") && ($5=="" || $5=="False")) next; else exit 1}'; then
            echo "✅ All submariner addons are Available=True and not Degraded!"
            echo ""

            # Final checks
            echo "📊 Broker status:"
            oc --context "$CLUSTER_1_NAME" -n "oc-clusters-broker" get Broker submariner-broker -o yaml 2>/dev/null | grep -A 10 "status:" || echo "Broker status not available"
            echo ""

            echo "🎉 Submariner verification completed successfully!"
            exit 0
        fi
    fi

    # Check for timeout
    if [ "$SECONDS" -ge "$TIMEOUT_SECONDS" ]; then
        echo ""
        echo "⛔ TIMEOUT: Submariner addons did not become healthy within ${TIMEOUT_SECONDS} seconds"
        echo ""
        echo "Current status:"
        oc --context "$CLUSTER_1_NAME" get managedclusteraddon -A | grep -E 'NAMESPACE|submariner'
        echo ""

        echo "🔍 Debugging information:"
        echo ""

        # Check broker
        echo "1. Broker status:"
        oc --context "$CLUSTER_1_NAME" -n "oc-clusters-broker" describe Broker submariner-broker 2>/dev/null || echo "Broker not found"
        echo ""

        # Check submariner operator pods
        echo "2. Submariner operator pods in each cluster:"
        echo ""
        echo "   Cluster 1 (local-cluster):"
        oc --context "$CLUSTER_1_NAME" -n submariner-operator get pods 2>/dev/null || echo "   No submariner-operator namespace"
        echo ""
        echo "   Cluster 2 ($CLUSTER_2_NAME):"
        oc --context "$CLUSTER_2_NAME" -n submariner-operator get pods 2>/dev/null || echo "   No submariner-operator namespace"
        echo ""

        # Check gateway nodes
        echo "3. Gateway nodes:"
        echo ""
        echo "   Cluster 1:"
        oc --context "$CLUSTER_1_NAME" get nodes -l submariner.io/gateway=true 2>/dev/null || echo "   No gateway nodes labeled"
        echo ""
        echo "   Cluster 2:"
        oc --context "$CLUSTER_2_NAME" get nodes -l submariner.io/gateway=true 2>/dev/null || echo "   No gateway nodes labeled"
        echo ""

        # Check addon conditions for each cluster
        echo "4. Detailed addon conditions:"
        for cluster in local-cluster "$CLUSTER_2_NAME"; do
            echo ""
            echo "   Cluster: $cluster"
            if oc --context "$CLUSTER_1_NAME" get managedclusteraddon submariner -n "$cluster" &>/dev/null; then
                oc --context "$CLUSTER_1_NAME" get managedclusteraddon submariner -n "$cluster" -o yaml | grep -A 30 "conditions:"
            else
                echo "   No submariner addon found in namespace $cluster"
            fi
        done
        echo ""

        # Check SubmarinerConfig
        echo "5. SubmarinerConfig status:"
        for cluster in local-cluster "$CLUSTER_2_NAME"; do
            echo ""
            echo "   Cluster: $cluster"
            if oc --context "$CLUSTER_1_NAME" get submarinerconfig -n "$cluster" &>/dev/null; then
                oc --context "$CLUSTER_1_NAME" get submarinerconfig -n "$cluster" -o yaml
            else
                echo "   No SubmarinerConfig found in namespace $cluster"
            fi
        done
        echo ""

        # Suggest fixes
        echo "🔧 Suggested troubleshooting steps:"
        echo ""
        echo "1. Check if gateway nodes have the proper label:"
        echo "   ./list-nodes-brokers.sh"
        echo ""
        echo "2. Verify network connectivity between clusters"
        echo ""
        echo "3. Check firewall rules - Submariner requires:"
        echo "   - UDP port 4500 (IPsec NAT traversal)"
        echo "   - UDP port 4490 (for encapsulated traffic)"
        echo "   - ESP protocol (IP protocol 50)"
        echo ""
        echo "4. Check logs from submariner-gateway pods:"
        echo "   oc --context \"\$CLUSTER_1_NAME\" -n submariner-operator logs -l app=submariner-gateway"
        echo "   oc --context \"\$CLUSTER_2_NAME\" -n submariner-operator logs -l app=submariner-gateway"
        echo ""
        echo "5. Verify ManagedClusterSet is configured correctly:"
        echo "   oc --context \"\$CLUSTER_1_NAME\" get managedclusterset oc-clusters -o yaml"
        echo ""

        exit 1
    fi

    # Show periodic diagnostics
    if [ $((SECONDS % 60)) -eq 0 ] && [ "$SECONDS" -gt 0 ]; then
        echo ""
        echo "📊 Periodic check - Broker status:"
        oc --context "$CLUSTER_1_NAME" -n "oc-clusters-broker" get Broker submariner-broker 2>/dev/null || echo "Broker not found or not ready"
        echo ""
    fi

    sleep 10
done

# Example expected output:
# NAMESPACE          NAME                          AVAILABLE   DEGRADED   PROGRESSING
# cluster-region-2   submariner                    True                   False
# local-cluster      submariner                    True                   False

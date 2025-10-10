#!/bin/bash

# TODO: once it works, revert this as it's exposed to doc

# Timeout after 20 minutes (1200 seconds)
TIMEOUT_SECONDS=1200
SECONDS=0

while true; do
    STATUS=$(oc --context "$CLUSTER_1_NAME" get managedclusters)
    echo "$STATUS"

    # Check if all clusters are healthy
    if echo "$STATUS" | awk 'NR>1 {if ($2=="true" && $4=="True" && $5=="True") next; else exit 1}'; then
        echo "✅ All managed clusters are Accepted=True, Joined=True, and Available=True!"
        exit 0
    fi

    # Check for Unknown or problematic states
    if echo "$STATUS" | grep -i "unknown"; then
        echo "⚠️  WARNING: Found cluster(s) in Unknown state:"
        echo "$STATUS" | grep -i "unknown"

        # Get detailed status for debugging
        for cluster in $(echo "$STATUS" | awk 'NR>1 && tolower($0) ~ /unknown/ {print $1}'); do
            echo ""
            echo "🔍 Debugging cluster: $cluster"
            echo "--- ManagedCluster details ---"
            oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster" -o yaml | tail -n 50

            echo ""
            echo "--- Checking klusterlet-addon-controller logs in namespace $cluster ---"
            if oc --context "$CLUSTER_1_NAME" get namespace "$cluster" &>/dev/null; then
                oc --context "$CLUSTER_1_NAME" -n "$cluster" get pods
                # Try to get klusterlet pods logs
                for pod in $(oc --context "$CLUSTER_1_NAME" -n "$cluster" get pods -l app=klusterlet -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
                    echo "Logs from pod: $pod"
                    oc --context "$CLUSTER_1_NAME" -n "$cluster" logs "$pod" --tail=30 || true
                done
            fi

            echo ""
            echo "--- Checking open-cluster-management-agent namespace on hub ---"
            if oc --context "$CLUSTER_1_NAME" get namespace "open-cluster-management-agent" &>/dev/null; then
                oc --context "$CLUSTER_1_NAME" -n "open-cluster-management-agent" get pods
            fi

            echo ""
            echo "--- Checking manifestwork status ---"
            oc --context "$CLUSTER_1_NAME" -n "$cluster" get manifestwork 2>/dev/null || echo "No manifestwork found"
        done
    fi

    # Check for timeout
    if [ "$SECONDS" -ge "$TIMEOUT_SECONDS" ]; then
        echo ""
        echo "⛔ TIMEOUT: Managed clusters did not become healthy within ${TIMEOUT_SECONDS} seconds"
        echo ""
        echo "Current status:"
        echo "$STATUS"
        echo ""
        echo "Attempting to diagnose and fix issues..."

        # Try to force reconciliation by patching problematic clusters
        for cluster in $(echo "$STATUS" | awk 'NR>1 && ($2!="true" || $4!="True" || $5!="True") {print $1}'); do
            echo "Attempting to force reconciliation for cluster: $cluster"

            # Check if the auto-import-secret exists and is valid
            if oc --context "$CLUSTER_1_NAME" get secret auto-import-secret -n "$cluster" &>/dev/null; then
                echo "✅ auto-import-secret exists in namespace $cluster"
                # Verify token is not expired
                TOKEN=$(oc --context "$CLUSTER_1_NAME" get secret auto-import-secret -n "$cluster" -o jsonpath='{.data.token}' | base64 -d)
                SERVER=$(oc --context "$CLUSTER_1_NAME" get secret auto-import-secret -n "$cluster" -o jsonpath='{.data.server}' | base64 -d)
                echo "Server: $SERVER"
                # Test if token is valid (basic check)
                if [ -z "$TOKEN" ] || [ -z "$SERVER" ]; then
                    echo "⚠️  Token or server is empty! This will prevent import."
                fi
            else
                echo "❌ auto-import-secret NOT found in namespace $cluster - this is a critical issue!"
            fi

            # Force update of the ManagedCluster
            oc --context "$CLUSTER_1_NAME" annotate managedcluster "$cluster" \
                import.open-cluster-management.io/retry="$(date +%s)" --overwrite || true
        done

        echo ""
        echo "Waiting 60 more seconds for forced reconciliation..."
        sleep 60

        # Final check
        FINAL_STATUS=$(oc --context "$CLUSTER_1_NAME" get managedclusters)
        echo "Final status after reconciliation attempt:"
        echo "$FINAL_STATUS"

        if echo "$FINAL_STATUS" | awk 'NR>1 {if ($2=="true" && $4=="True" && $5=="True") next; else exit 1}'; then
            echo "✅ Clusters recovered after forced reconciliation!"
            exit 0
        else
            echo "❌ Clusters still unhealthy after timeout and reconciliation attempts"
            exit 1
        fi
    fi

    echo "⏳ Waiting for all clusters to become healthy... (${SECONDS}s / ${TIMEOUT_SECONDS}s)"
    sleep 10
done

# Example output:
# NAME            HUB ACCEPTED   MANAGED CLUSTER URLS                                 JOINED   AVAILABLE   AGE
# cl-oc-2         true           https://api.cl-oc-2.5egh.p3.openshiftapps.com:443    True     True        50s
# local-cluster   true           https://api.cl-oc-1.f70c.p3.openshiftapps.com:443   True     True        36m

#!/bin/bash

# TODO:  once it works, revert this as it's exposed to doc

set -euo pipefail

echo "🚀 Starting cluster import process..."
echo ""

# Function to validate token and API
validate_cluster_access() {
    local context=$1
    local token=$2
    local api=$3

    echo "  ✓ Context: $context"
    echo "  ✓ API Server: $api"
    echo "  ✓ Token length: ${#token} characters"

    # Verify we can actually access the cluster
    if ! oc --context "$context" whoami &>/dev/null; then
        echo "  ⚠️  WARNING: Cannot verify access to cluster using context $context"
        return 1
    fi

    echo "  ✅ Successfully verified cluster access"
    return 0
}

# Function to extract CA certificate from managed cluster for auto-import
extract_managed_cluster_ca() {
    local context=$1

    echo "   Extracting CA certificate from managed cluster..."

    # Try to get CA from the kubeconfig
    local ca_data
    ca_data=$(oc config view --context "$context" --raw -o json | jq -r '.clusters[0].cluster."certificate-authority-data"' 2>/dev/null || echo "")

    if [ -n "$ca_data" ] && [ "$ca_data" != "null" ]; then
        # CA is embedded in kubeconfig, decode it
        # Extract ONLY the LAST certificate in the chain (the root CA)
        echo "$ca_data" | base64 -d | awk '
            /BEGIN CERTIFICATE/ { cert = $0; next }
            cert { cert = cert "\n" $0 }
            /END CERTIFICATE/ { last_cert = cert "\n" $0; cert = "" }
            END { print last_cert }
        '
        return 0
    fi

    echo "  ⚠️  WARNING: Could not extract CA certificate from managed cluster" >&2
    return 1
}

# Function to wait for ACM import pods
wait_for_import_pods() {
    local cluster_name=$1
    local max_wait=120  # 2 minutes
    local elapsed=0

    echo "  ⏳ Waiting for ACM import pods to start..."

    while [ $elapsed -lt $max_wait ]; do
        local pod_count
        pod_count=$(oc --context "$CLUSTER_1_NAME" get pods -n "$cluster_name" --no-headers 2>/dev/null | wc -l | tr -d ' ')

        if [ "$pod_count" -gt 0 ]; then
            echo "  ✅ Import pods detected in namespace $cluster_name"
            oc --context "$CLUSTER_1_NAME" get pods -n "$cluster_name"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))

        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  ⏱️  Still waiting for import pods... (${elapsed}s elapsed)"
        fi
    done

    echo "  ⚠️  WARNING: No import pods detected after ${max_wait}s"
    echo "  This may indicate an issue with the auto-import-secret configuration"
    return 1
}

# Function to import a cluster with retries
import_cluster() {
    local cluster_name=$1
    local cluster_token=$2
    local cluster_api=$3
    local context=$4

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📥 Importing cluster: $cluster_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ! validate_cluster_access "$context" "$cluster_token" "$cluster_api"; then
        echo "❌ Failed to validate cluster access for $cluster_name"
        return 1
    fi

    # Extract CA certificate from the managed cluster (not hub!)
    # This CA is needed for the hub's import process to connect to the managed cluster's API
    local ca_cert
    if ! ca_cert=$(extract_managed_cluster_ca "$context"); then
        echo "❌ Failed to extract CA certificate from managed cluster"
        return 1
    fi
    echo "  ✅ CA certificate extracted successfully from managed cluster"

    # Ensure namespace exists first
    if ! oc --context "$CLUSTER_1_NAME" get namespace "$cluster_name" &>/dev/null; then
        echo "Creating namespace: $cluster_name"
        oc --context "$CLUSTER_1_NAME" create namespace "$cluster_name" || true
        # Wait for namespace to be ready
        sleep 2
    else
        echo "✓ Namespace $cluster_name already exists"
    fi

    # Apply ManagedCluster
    echo "  ⏳ Creating ManagedCluster resource..."
    CLUSTER_NAME="$cluster_name" envsubst < managed-cluster.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

    # Wait a bit for the namespace to be fully created by ACM
    echo "  ⏳ Waiting for ACM to setup cluster namespace..."
    sleep 5

    # Create auto-import-secret with CA certificate
    # This secret allows the hub to connect to the managed cluster and deploy the klusterlet
    echo "  ⏳ Creating auto-import-secret for ACM auto-import..."

    # Delete existing secret if it exists
    oc --context "$CLUSTER_1_NAME" delete secret auto-import-secret -n "$cluster_name" &>/dev/null || true

    # Save CA cert to a temporary file (needed for --from-file)
    local ca_cert_file
    ca_cert_file=$(mktemp)
    echo "$ca_cert" > "$ca_cert_file"

    # Create the auto-import-secret with proper configuration
    # ACM will use this to:
    # 1. Connect to the managed cluster API
    # 2. Deploy the klusterlet operator and agent
    # 3. Create the bootstrap-hub-kubeconfig automatically on the managed cluster
    if oc --context "$CLUSTER_1_NAME" create secret generic auto-import-secret \
        -n "$cluster_name" \
        --from-literal=autoImportRetry=5 \
        --from-literal=token="$cluster_token" \
        --from-literal=server="$cluster_api" \
        --from-file=ca.crt="$ca_cert_file"; then
        echo "  ✅ auto-import-secret created successfully"
        echo "  📦 ACM will now automatically deploy klusterlet and configure bootstrap"
        rm -f "$ca_cert_file"
    else
        echo "  ❌ Failed to create auto-import-secret"
        rm -f "$ca_cert_file"
        return 1
    fi

    # Apply KlusterletAddonConfig
    echo "  ⏳ Creating KlusterletAddonConfig..."
    CLUSTER_NAME="$cluster_name" envsubst < klusterlet-config.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

    # Wait for ACM to process the auto-import-secret and start import pods
    echo "  ⏳ Waiting for ACM to process auto-import-secret..."
    sleep 10

    # Verify that import pods are starting
    if ! wait_for_import_pods "$cluster_name"; then
        echo "  ⚠️  Import pods not detected - checking configuration..."
        echo ""
        echo "  🔍 Auto-import-secret status:"
        oc --context "$CLUSTER_1_NAME" get secret auto-import-secret -n "$cluster_name" -o yaml 2>/dev/null || echo "  ❌ Secret not found"
        echo ""
        echo "  � ManagedCluster status:"
        oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" -o yaml 2>/dev/null || echo "  ❌ ManagedCluster not found"
    fi

    # Check initial status
    echo "  📊 Initial status:"
    oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" || echo "  ⚠️  ManagedCluster not found yet"

    echo ""
    echo "✅ Import initiated for cluster: $cluster_name"
    echo "   ACM will automatically handle klusterlet deployment and bootstrap configuration"
}

# Import first cluster (local-cluster)
echo "1️⃣  CLUSTER 1: local-cluster"
SUB1_TOKEN=$(oc --context "$CLUSTER_1_NAME" whoami -t)
CLUSTER_1_API=$(oc config view --minify --context "$CLUSTER_1_NAME" --raw -o json | jq -r '.clusters[].cluster.server')

if [ -z "$SUB1_TOKEN" ] || [ -z "$CLUSTER_1_API" ]; then
    echo "❌ Failed to get token or API for Cluster 1"
    exit 1
fi

# For the first cluster, the cluster name is hardcoded on purpose
import_cluster "local-cluster" "$SUB1_TOKEN" "$CLUSTER_1_API" "$CLUSTER_1_NAME"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Import second cluster
echo "2️⃣  CLUSTER 2: $CLUSTER_2_NAME"
SUB2_TOKEN=$(oc --context "$CLUSTER_2_NAME" whoami -t)
CLUSTER_2_API=$(oc config view --minify --context "$CLUSTER_2_NAME" --raw -o json | jq -r '.clusters[].cluster.server')

if [ -z "$SUB2_TOKEN" ] || [ -z "$CLUSTER_2_API" ]; then
    echo "❌ Failed to get token or API for Cluster 2"
    exit 1
fi

import_cluster "$CLUSTER_2_NAME" "$SUB2_TOKEN" "$CLUSTER_2_API" "$CLUSTER_2_NAME"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
oc --context "$CLUSTER_1_NAME" get managedclusters
echo ""
echo "✅ Cluster import process completed!"
echo ""
echo "⏳ Note: It may take 5-10 minutes for clusters to become fully Available."
echo "   Run './verify-managed-cluster-set.sh' to wait for clusters to be ready."
echo ""
echo "🔍 For debugging, use: ./debug-managed-cluster.sh <cluster-name>"
echo ""

# Example expected output:
# NAME            HUB ACCEPTED   MANAGED CLUSTER URLS                                 JOINED   AVAILABLE   AGE
# cl-oc-2         true           https://api.cl-oc-2.5egh.p3.openshiftapps.com:443    True     True        50s
# local-cluster   true           https://api.cl-oc-1.f70c.p3.openshiftapps.com:443   True     True        36m

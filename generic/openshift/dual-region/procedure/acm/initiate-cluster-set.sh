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

# Function to extract CA certificate from HUB cluster for auto-import
# The CA must be from the HUB so the klusterlet on the managed cluster can verify
# the hub's API server certificate when connecting back to the hub
extract_hub_cluster_ca() {
    echo "  🔐 Extracting CA certificate from hub's kube-root-ca ConfigMap..."

    # Get CA certificate directly from kube-root-ca.crt ConfigMap in kube-system on the HUB
    # This ConfigMap contains the root CA that OpenShift uses
    local ca_from_cm
    ca_from_cm=$(oc --context "$CLUSTER_1_NAME" get configmap kube-root-ca.crt -n kube-system -o jsonpath='{.data.ca\.crt}' 2>/dev/null || echo "")

    if [ -n "$ca_from_cm" ]; then
        # Extract ONLY the FIRST certificate (the root CA, not Let's Encrypt intermediates)
        echo "$ca_from_cm" | awk '
            /BEGIN CERTIFICATE/ { cert = $0; in_cert = 1; next }
            in_cert { cert = cert "\n" $0 }
            /END CERTIFICATE/ {
                if (!printed) {
                    print cert "\n" $0
                    printed = 1
                }
                cert = ""
                in_cert = 0
            }
        '
        return 0
    fi

    echo "  ⚠️  WARNING: Could not extract CA certificate from hub's kube-root-ca ConfigMap" >&2
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

    # Extract CA certificate from the HUB cluster (not the managed cluster!)
    # This CA is needed so the klusterlet on the managed cluster can verify
    # the hub's API server certificate when connecting back to the hub
    echo "  🔐 Extracting hub CA certificate for klusterlet authentication..."
    local ca_cert
    if ! ca_cert=$(extract_hub_cluster_ca); then
        echo "❌ Failed to extract CA certificate from hub cluster"
        return 1
    fi
    echo "  ✅ Hub CA certificate extracted successfully"

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

    # Create auto-import-secret with CA certificate from the HUB
    # This secret configures ACM to:
    # 1. Connect to the managed cluster API using token/server (managed cluster credentials)
    # 2. Deploy the klusterlet with the hub's CA certificate
    # 3. Allow the klusterlet to verify the hub's API server certificate
    echo "  ⏳ Creating auto-import-secret for ACM auto-import..."

    # Delete existing secret if it exists
    oc --context "$CLUSTER_1_NAME" delete secret auto-import-secret -n "$cluster_name" &>/dev/null || true

    # Save hub CA cert to a temporary file (needed for --from-file)
    local ca_cert_file
    ca_cert_file=$(mktemp)
    echo "$ca_cert" > "$ca_cert_file"

    # Create the auto-import-secret with proper configuration:
    # - token: managed cluster token (for hub to connect TO managed cluster)
    # - server: managed cluster API (for hub to connect TO managed cluster)
    # - ca.crt: HUB cluster CA (for klusterlet to verify hub's certificate)
    if oc --context "$CLUSTER_1_NAME" create secret generic auto-import-secret \
        -n "$cluster_name" \
        --from-literal=autoImportRetry=5 \
        --from-literal=token="$cluster_token" \
        --from-literal=server="$cluster_api" \
        --from-file=ca.crt="$ca_cert_file"; then
        echo "  ✅ auto-import-secret created successfully"
        echo "  📦 ACM will now automatically deploy klusterlet with hub CA"
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

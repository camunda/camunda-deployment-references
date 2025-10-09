#!/bin/bash

# TODO: once it works, revert this as it's exposed to doc

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

# Function to extract CA certificate from cluster
extract_ca_certificate() {
    local context=$1

    echo "  🔐 Extracting CA certificate from cluster..."

    # Try to get CA from the kubeconfig
    local ca_data
    ca_data=$(oc config view --context "$context" --raw -o json | jq -r '.clusters[0].cluster."certificate-authority-data"' 2>/dev/null || echo "")

    if [ -n "$ca_data" ] && [ "$ca_data" != "null" ]; then
        # CA is embedded in kubeconfig, decode it
        echo "$ca_data" | base64 -d
        return 0
    fi

    # Fallback: try to get from kube-root-ca ConfigMap
    local ca_from_cm
    ca_from_cm=$(oc --context "$context" get configmap kube-root-ca.crt -n kube-system -o jsonpath='{.data.ca\.crt}' 2>/dev/null || echo "")

    if [ -n "$ca_from_cm" ]; then
        echo "$ca_from_cm"
        return 0
    fi

    echo "  ⚠️  WARNING: Could not extract CA certificate" >&2
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

    # Extract CA certificate from the hub cluster (CLUSTER_1_NAME)
    # This is needed for the managed cluster to trust the hub's API server
    local ca_cert
    if ! ca_cert=$(extract_ca_certificate "$CLUSTER_1_NAME"); then
        echo "❌ Failed to extract CA certificate from hub cluster"
        return 1
    fi
    echo "  ✅ CA certificate extracted successfully"

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

    # Apply auto-import-secret with CA certificate
    echo "  ⏳ Creating auto-import-secret with CA certificate..."
    # Indent the CA cert for YAML formatting
    local cluster_ca_cert_indented
    cluster_ca_cert_indented=${ca_cert//$'\n'/$'\n    '}

    CLUSTER_NAME="$cluster_name" \
    CLUSTER_TOKEN="$cluster_token" \
    CLUSTER_API="$cluster_api" \
    CLUSTER_CA_CERT="$cluster_ca_cert_indented" \
        envsubst < auto-import-cluster-secret.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

    # Verify secret was created
    if oc --context "$CLUSTER_1_NAME" get secret auto-import-secret -n "$cluster_name" &>/dev/null; then
        echo "  ✅ auto-import-secret created successfully"
    else
        echo "  ❌ Failed to create auto-import-secret"
        return 1
    fi

    # Apply KlusterletAddonConfig
    echo "  ⏳ Creating KlusterletAddonConfig..."
    CLUSTER_NAME="$cluster_name" envsubst < klusterlet-config.yml.tpl | oc --context "$CLUSTER_1_NAME" apply -f -

    # Wait for initial import to start
    echo "  ⏳ Waiting for import process to initialize (30s)..."
    sleep 30

    # Check initial status
    echo "  📊 Initial status:"
    oc --context "$CLUSTER_1_NAME" get managedcluster "$cluster_name" || echo "  ⚠️  ManagedCluster not found yet"

    # Check for import pods
    echo ""
    echo "  📦 Checking import pods in namespace $cluster_name:"
    oc --context "$CLUSTER_1_NAME" -n "$cluster_name" get pods 2>/dev/null || echo "  ⚠️  No pods found yet (this is normal initially)"

    echo ""
    echo "✅ Import initiated for cluster: $cluster_name"
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

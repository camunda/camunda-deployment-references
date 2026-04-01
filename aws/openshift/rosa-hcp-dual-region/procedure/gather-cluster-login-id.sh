#!/bin/bash

# Cluster 0
export CLUSTER_0_NAME="$(terraform console <<<local.rosa_cluster_0_name | tail -n 1 | jq -r)"
export CLUSTER_0_API_URL="$(terraform output -raw cluster_0_openshift_api_url)"
export CLUSTER_0_ADMIN_USERNAME="$(terraform console <<<local.rosa_cluster_0_admin_username | tail -n 1 | jq -r)"
export CLUSTER_0_ADMIN_PASSWORD="$(terraform output -raw rosa_cluster_0_admin_password)"

echo "CLUSTER_0_NAME=$CLUSTER_0_NAME"
echo "CLUSTER_0_API_URL=$CLUSTER_0_API_URL"
echo "CLUSTER_0_ADMIN_USERNAME=$CLUSTER_0_ADMIN_USERNAME"

# Cluster 1
export CLUSTER_1_NAME="$(terraform console <<<local.rosa_cluster_1_name | tail -n 1 | jq -r)"
export CLUSTER_1_API_URL="$(terraform output -raw cluster_1_openshift_api_url)"
export CLUSTER_1_ADMIN_USERNAME="$(terraform console <<<local.rosa_cluster_1_admin_username | tail -n 1 | jq -r)"
export CLUSTER_1_ADMIN_PASSWORD="$(terraform output -raw rosa_cluster_1_admin_password)"

echo "CLUSTER_1_NAME=$CLUSTER_1_NAME"
echo "CLUSTER_1_API_URL=$CLUSTER_1_API_URL"
echo "CLUSTER_1_ADMIN_USERNAME=$CLUSTER_1_ADMIN_USERNAME"

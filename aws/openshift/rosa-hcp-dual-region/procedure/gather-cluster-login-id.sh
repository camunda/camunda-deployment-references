#!/bin/bash

# Cluster 1
export CLUSTER_1_NAME="$(terraform console <<<local.rosa_cluster_1_name | tail -n 1 | jq -r)"
export CLUSTER_1_API_URL=$(terraform output -raw cluster_1_openshift_api_url)
export CLUSTER_1_ADMIN_USERNAME="$(terraform console <<<local.rosa_cluster_1_admin_username | tail -n 1 | jq -r)"
export CLUSTER_1_ADMIN_PASSWORD="$(terraform console <<<local.rosa_cluster_1_admin_password | tail -n 1 | jq -r)"

echo "CLUSTER_1_NAME=$CLUSTER_1_NAME"
echo "CLUSTER_1_API_URL=$CLUSTER_1_API_URL"
echo "CLUSTER_1_ADMIN_USERNAME=$CLUSTER_1_ADMIN_USERNAME"

# Cluster 2
export CLUSTER_2_NAME="$(terraform console <<<local.rosa_cluster_2_name | tail -n 1 | jq -r)"
export CLUSTER_2_API_URL=$(terraform output -raw cluster_2_openshift_api_url)
export CLUSTER_2_ADMIN_USERNAME="$(terraform console <<<local.rosa_cluster_2_admin_username | tail -n 1 | jq -r)"
export CLUSTER_2_ADMIN_PASSWORD="$(terraform console <<<local.rosa_cluster_2_admin_password | tail -n 1 | jq -r)"

echo "CLUSTER_2_NAME=$CLUSTER_2_NAME"
echo "CLUSTER_2_API_URL=$CLUSTER_2_API_URL"
echo "CLUSTER_2_ADMIN_USERNAME=$CLUSTER_2_ADMIN_USERNAME"

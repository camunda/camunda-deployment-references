#!/bin/bash

CLUSTER_NAME="$(terraform console <<<local.rosa_cluster_name | tail -n 1 | jq -r)"
export CLUSTER_NAME
CLUSTER_API_URL="$(terraform output -raw openshift_api_url)"
export CLUSTER_API_URL
CLUSTER_ADMIN_USERNAME="$(terraform console <<<local.rosa_admin_username | tail -n 1 | jq -r)"
export CLUSTER_ADMIN_USERNAME
CLUSTER_ADMIN_PASSWORD="$(terraform output -raw rosa_admin_password)"
export CLUSTER_ADMIN_PASSWORD

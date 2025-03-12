#!/bin/bash

export CLUSTER_NAME="$(terraform console <<<local.rosa_cluster_name | jq -r)"
export CLUSTER_API_URL=$(terraform output -raw openshift_api_url)
export CLUSTER_ADMIN_USERNAME="$(terraform console <<<local.rosa_admin_username | jq -r)"
export CLUSTER_ADMIN_PASSWORD="$(terraform console <<<local.rosa_admin_password | jq -r)"

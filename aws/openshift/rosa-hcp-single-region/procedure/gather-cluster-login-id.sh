#!/bin/bash

export CLUSTER_NAME="$(terraform console <<<local.rosa_cluster_name | tail -n 1 | jq -r)"
export CLUSTER_API_URL=$(terraform output -raw openshift_api_url)
export CLUSTER_ADMIN_USERNAME="$(terraform console <<<local.rosa_admin_username | tail -n 1 | jq -r)"
export CLUSTER_ADMIN_PASSWORD="$(terraform console <<<local.rosa_admin_password | tail -n 1 | jq -r)"

#!/bin/bash

# Preserve export's masked substitution status when errexit is enabled.
CLUSTER_NAME="$(terraform console <<<local.rosa_cluster_name | tail -n 1 | jq -r)" || true
export CLUSTER_NAME
CLUSTER_API_URL=$(terraform output -raw openshift_api_url) || true
export CLUSTER_API_URL
CLUSTER_ADMIN_USERNAME="$(terraform console <<<local.rosa_admin_username | tail -n 1 | jq -r)" || true
export CLUSTER_ADMIN_USERNAME
CLUSTER_ADMIN_PASSWORD="$(terraform console <<<local.rosa_admin_password | tail -n 1 | jq -r)" || true
export CLUSTER_ADMIN_PASSWORD

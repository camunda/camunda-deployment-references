#!/bin/bash

# Preserve export's masked substitution status when errexit is enabled.
AURORA_ENDPOINT=$(terraform output -raw postgres_endpoint) || true
export AURORA_ENDPOINT
export AURORA_PORT=5432

# PostgreSQL Credentials (replace with your own values from the #postgresql-module-setup step)
AURORA_USERNAME="$(terraform console <<<local.aurora_master_username | tail -n 1 | jq -r)" || true
export AURORA_USERNAME
AURORA_PASSWORD="$(terraform console <<<local.aurora_master_password | tail -n 1 | jq -r)" || true
export AURORA_PASSWORD

#!/bin/bash

# Preserve export's masked substitution status when errexit is enabled.
AURORA_ENDPOINT="$(terraform output -raw postgres_endpoint)" || true
export AURORA_ENDPOINT
export AURORA_PORT=5432

# PostgreSQL Credentials
AURORA_USERNAME="$(terraform output -raw aurora_master_username)" || true
export AURORA_USERNAME
AURORA_PASSWORD="$(terraform output -raw aurora_master_password)" || true
export AURORA_PASSWORD

# PostgreSQL Major Version (e.g. 17)
POSTGRES_MAJOR_VERSION="$(terraform output -raw postgres_major_version)" || true
export POSTGRES_MAJOR_VERSION

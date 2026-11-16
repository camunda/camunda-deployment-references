#!/bin/bash

AURORA_ENDPOINT="$(terraform output -raw postgres_endpoint)"
export AURORA_ENDPOINT
export AURORA_PORT=5432

# PostgreSQL Credentials
AURORA_USERNAME="$(terraform output -raw aurora_master_username)"
export AURORA_USERNAME
AURORA_PASSWORD="$(terraform output -raw aurora_master_password)"
export AURORA_PASSWORD

# PostgreSQL Major Version (e.g. 17)
POSTGRES_MAJOR_VERSION="$(terraform output -raw postgres_major_version)"
export POSTGRES_MAJOR_VERSION

#!/bin/bash

export AURORA_ENDPOINT=$(terraform output -raw postgres_endpoint)
export AURORA_PORT=5432

# PostgreSQL Credentials
export AURORA_USERNAME=$(terraform output -raw aurora_master_username)
export AURORA_PASSWORD=$(terraform output -raw aurora_master_password)

# PostgreSQL Major Version (e.g. 17)
export POSTGRES_MAJOR_VERSION=$(terraform output -raw postgres_major_version)

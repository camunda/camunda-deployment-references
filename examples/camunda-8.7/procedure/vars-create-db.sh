export AURORA_ENDPOINT=$(terraform output -raw postgres_endpoint)
export AURORA_PORT=5432

# PostgreSQL Credentials (replace with your own values from the #postgresql-module-setup step)
export AURORA_USERNAME="$(terraform console <<<local.aurora_master_username | jq -r)"
export AURORA_PASSWORD="$(terraform console <<<local.aurora_master_password | jq -r)"

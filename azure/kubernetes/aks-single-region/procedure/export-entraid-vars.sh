#!/bin/bash
# Export EntraID variables from Terraform outputs

set -euo pipefail

# Get terraform outputs
outputs_json=$(terraform output -json)

# Azure Tenant ID
export AZURE_TENANT_ID=$(echo "$outputs_json" | jq -r .azure_tenant_id.value)

# Identity Initial Admin User Email
export IDENTITY_INITIAL_USER_EMAIL=$(echo "$outputs_json" | jq -r .identity_initial_user_email.value)

# Identity (Management Identity)
export IDENTITY_CLIENT_ID=$(echo "$outputs_json" | jq -r .identity_client_id.value)
export IDENTITY_CLIENT_SECRET=$(echo "$outputs_json" | jq -r .identity_client_secret.value)
export IDENTITY_AUDIENCE=$(echo "$outputs_json" | jq -r .identity_audience.value)

# Optimize
export OPTIMIZE_CLIENT_ID=$(echo "$outputs_json" | jq -r .optimize_client_id.value)
export OPTIMIZE_CLIENT_SECRET=$(echo "$outputs_json" | jq -r .optimize_client_secret.value)
export OPTIMIZE_AUDIENCE=$(echo "$outputs_json" | jq -r .optimize_audience.value)

# Orchestration Cluster (Operate, Tasklist, Zeebe)
export ORCHESTRATION_CLIENT_ID=$(echo "$outputs_json" | jq -r .orchestration_client_id.value)
export ORCHESTRATION_CLIENT_SECRET=$(echo "$outputs_json" | jq -r .orchestration_client_secret.value)
export ORCHESTRATION_AUDIENCE=$(echo "$outputs_json" | jq -r .orchestration_audience.value)

# Console (SPA - no secret)
export CONSOLE_CLIENT_ID=$(echo "$outputs_json" | jq -r .console_client_id.value)
export CONSOLE_AUDIENCE=$(echo "$outputs_json" | jq -r .console_audience.value)

# WebModeler (if enabled)
if [ "$(echo "$outputs_json" | jq -r '.webmodeler_ui_client_id.value // empty')" != "" ]; then
    export WEBMODELER_UI_CLIENT_ID=$(echo "$outputs_json" | jq -r .webmodeler_ui_client_id.value)
    export WEBMODELER_UI_AUDIENCE=$(echo "$outputs_json" | jq -r .webmodeler_ui_audience.value)
    export WEBMODELER_API_CLIENT_ID=$(echo "$outputs_json" | jq -r .webmodeler_api_client_id.value)
    export WEBMODELER_API_AUDIENCE=$(echo "$outputs_json" | jq -r .webmodeler_api_audience.value)
    export WEBMODELER_API_CLIENT_SECRET=$(echo "$outputs_json" | jq -r .webmodeler_api_client_secret.value)
fi

echo "EntraID variables exported successfully!"
echo "AZURE_TENANT_ID: $AZURE_TENANT_ID"
echo "IDENTITY_CLIENT_ID: $IDENTITY_CLIENT_ID"
echo "OPTIMIZE_CLIENT_ID: $OPTIMIZE_CLIENT_ID"
echo "ORCHESTRATION_CLIENT_ID: $ORCHESTRATION_CLIENT_ID"
echo "CONSOLE_CLIENT_ID: $CONSOLE_CLIENT_ID"

if [ -n "${WEBMODELER_UI_CLIENT_ID:-}" ]; then
    echo "WEBMODELER_UI_CLIENT_ID: $WEBMODELER_UI_CLIENT_ID"
    echo "WEBMODELER_API_CLIENT_ID: $WEBMODELER_API_CLIENT_ID"
fi

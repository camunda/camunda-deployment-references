#!/bin/bash

ZEEBE_ADDRESS_REST="https://$DOMAIN_NAME/core"
ZEEBE_AUTHORIZATION_SERVER_URL="https://$DOMAIN_NAME/auth/realms/camunda-platform/protocol/openid-connect/token"

# Generate a temporary token from the authorization server (keycloak)
TOKEN=$(curl --location --request POST "${ZEEBE_AUTHORIZATION_SERVER_URL}" \
--header "Content-Type: application/x-www-form-urlencoded" \
--data-urlencode "client_id=${ZEEBE_CLIENT_ID}" \
--data-urlencode "client_secret=${ZEEBE_CLIENT_SECRET}" \
--data-urlencode "grant_type=client_credentials" | jq '.access_token' -r)

# Show the zeebe cluster topology
curl --header "Authorization: Bearer ${TOKEN}" "${ZEEBE_ADDRESS_REST}/v2/topology"

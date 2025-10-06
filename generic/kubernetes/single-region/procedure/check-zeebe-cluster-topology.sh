#!/bin/bash

# Generate a temporary token from the authorization server (keycloak)
TOKEN=$(curl --silent --location --request POST "${ZEEBE_AUTHORIZATION_SERVER_URL}" \
--header "Content-Type: application/x-www-form-urlencoded" \
--data-urlencode "client_id=${ZEEBE_CLIENT_ID}" \
--data-urlencode "client_secret=${ZEEBE_CLIENT_SECRET}" \
--data-urlencode "grant_type=client_credentials" | jq '.access_token' -r)

# Show the zeebe cluster topology
echo "📡 Fetching Zeebe cluster topology from: ${ZEEBE_ADDRESS_REST}/v2/topology"
topology=$(curl --silent --header "Authorization: Bearer ${TOKEN}" "${ZEEBE_ADDRESS_REST}/v2/topology")

echo "$topology" > zeebe-topology.json

jq . zeebe-topology.json

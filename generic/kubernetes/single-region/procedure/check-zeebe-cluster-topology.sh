#!/bin/bash

# Orchestration Cluster basic auth
TOKEN="Basic ZGVtbzpkZW1v"

if [ -n "${ZEEBE_CLIENT_ID}" ] && [ -n "${ZEEBE_CLIENT_SECRET}" ]; then
  # Generate a temporary token from the authorization server (keycloak)
  TOKEN=$(curl --location --request POST "${ZEEBE_AUTHORIZATION_SERVER_URL}" \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "client_id=${ZEEBE_CLIENT_ID}" \
  --data-urlencode "client_secret=${ZEEBE_CLIENT_SECRET}" \
  --data-urlencode "grant_type=client_credentials" | jq '.access_token' -r)

  TOKEN="Bearer ${TOKEN}"
fi

# Show the zeebe cluster topology
echo "📡 Fetching Zeebe cluster topology..."
topology=$(curl --header "Authorization: ${TOKEN}" "${ZEEBE_ADDRESS_REST}/v2/topology")

echo "$topology" > zeebe-topology.json

jq . zeebe-topology.json

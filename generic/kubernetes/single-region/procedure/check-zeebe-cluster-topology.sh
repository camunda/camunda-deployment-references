#!/bin/bash

# Generate a temporary token from the authorization server (keycloak)
# TODO: Remove debug output once authentication issues are resolved
echo "🔐 Requesting token from: ${ZEEBE_AUTHORIZATION_SERVER_URL}"
echo "   Client ID: ${ZEEBE_CLIENT_ID}"
TOKEN=$(curl -v --location --request POST "${ZEEBE_AUTHORIZATION_SERVER_URL}" \
--header "Content-Type: application/x-www-form-urlencoded" \
--data-urlencode "client_id=${ZEEBE_CLIENT_ID}" \
--data-urlencode "client_secret=${ZEEBE_CLIENT_SECRET}" \
--data-urlencode "grant_type=client_credentials" 2>&1 | tee /tmp/token-request.log | jq '.access_token' -r)

# TODO: Remove token debug once authentication issues are resolved
echo "🔑 Token received (first 20 chars): ${TOKEN:0:20}..."
echo "   Token length: ${#TOKEN}"

# Show the zeebe cluster topology
echo "📡 Fetching Zeebe cluster topology from: ${ZEEBE_ADDRESS_REST}/v2/topology"
# TODO: Remove verbose curl once authentication issues are resolved
topology=$(curl -v --header "Authorization: Bearer ${TOKEN}" "${ZEEBE_ADDRESS_REST}/v2/topology" 2>&1 | tee /tmp/topology-request.log)

# TODO: Remove topology debug output once authentication issues are resolved
echo "📊 Raw topology response:"
echo "$topology"
echo ""

echo "$topology" > zeebe-topology.json

echo "📊 Formatted topology:"
jq . zeebe-topology.json

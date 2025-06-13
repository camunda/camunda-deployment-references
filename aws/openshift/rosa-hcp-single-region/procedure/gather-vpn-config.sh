#!/bin/bash

# Set the client name as defined in the module
client="my-client"

vpn_client_configs="$(terraform output -json vpn_client_configs)"

# Extract the configuration for the specified client
config=$(echo "$vpn_client_configs" | jq -r --arg client "$client" '.[$client]')


# Write the configuration to a .ovpn file
echo "$config" > "./$client.ovpn"

echo "Configuration file created: ./$client.ovpn"

#!/bin/bash

export ZEEBE_ADDRESS_REST="https://$DOMAIN_NAME/core"
export ZEEBE_AUTHORIZATION_SERVER_URL="https://$DOMAIN_NAME/auth/realms/camunda-platform/protocol/openid-connect/token"

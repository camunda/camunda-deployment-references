#!/bin/bash

export ZEEBE_ADDRESS_REST="https://$CAMUNDA_DOMAIN"
export ZEEBE_AUTHORIZATION_SERVER_URL="https://$CAMUNDA_DOMAIN/auth/realms/camunda-platform/protocol/openid-connect/token"

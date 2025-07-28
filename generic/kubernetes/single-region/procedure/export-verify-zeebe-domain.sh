#!/bin/bash
# TODO; update the variables with CAMUNDA_CLIENT_ZEEBE_RESTADDRESS CAMUNDA_CLIENT_AUTH_TOKENURL (see https://github.com/camunda-community-hub/camunda-8-examples/blob/main/payment-example-process-application/kube/README.md)
export ZEEBE_ADDRESS_REST="https://$DOMAIN_NAME/core"
export ZEEBE_AUTHORIZATION_SERVER_URL="https://$DOMAIN_NAME/auth/realms/camunda-platform/protocol/openid-connect/token"

#!/bin/bash

# TODO: 8;8 generate USER_PASSWORD

kubectl create secret generic identity-secret-for-components \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=identity-connectors-client-token="$CONNECTORS_SECRET" \
  --from-literal=identity-console-client-token="$CONSOLE_SECRET" \
  --from-literal=identity-optimize-client-token="$OPTIMIZE_SECRET" \
  --from-literal=identity-core-client-token="$ZEEBE_SECRET" \
  --from-literal=identity-admin-client-token="$ADMIN_PASSWORD" \
  --from-literal=identity-firstuser-password="$USER_PASSWORD" \
  --from-literal=smtp-password=""

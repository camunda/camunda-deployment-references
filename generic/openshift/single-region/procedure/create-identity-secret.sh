#!/bin/bash

oc create secret generic identity-secret-for-components \
  --namespace "$CAMUNDA_NAMESPACE" \
  --from-literal=connectors-secret="$CONNECTORS_SECRET" \
  --from-literal=console-secret="$CONSOLE_SECRET" \
  --from-literal=operate-secret="$OPERATE_SECRET" \
  --from-literal=optimize-secret="$OPTIMIZE_SECRET" \
  --from-literal=tasklist-secret="$TASKLIST_SECRET" \
  --from-literal=zeebe-secret="$ZEEBE_SECRET" \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --from-literal=smtp-password=""

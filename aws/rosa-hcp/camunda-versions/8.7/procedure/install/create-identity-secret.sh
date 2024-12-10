kubectl create secret generic identity-secret-for-components \
  --namespace camunda \
  --from-literal=connectors-secret="$CONNECTORS_SECRET" \
  --from-literal=console-secret="$CONSOLE_SECRET" \
  --from-literal=core-secret="$CORE_SECRET" \
  --from-literal=optimize-secret="$OPTIMIZE_SECRET" \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --from-literal=postgres-password="" \
  --from-literal=password="" \
  --from-literal=smtp-password=""

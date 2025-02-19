kubectl create secret generic setup-os-secret --namespace camunda \
  --from-literal=OPENSEARCH_HOST="$OPENSEARCH_HOST" \
  --from-literal=OPENSEARCH_ROLE_ARN="$OPENSEARCH_ROLE_ARN" \
  --from-literal=OPENSEARCH_MASTER_USERNAME="$OPENSEARCH_MASTER_USERNAME" \
  --from-literal=OPENSEARCH_MASTER_PASSWORD="$OPENSEARCH_MASTER_PASSWORD"

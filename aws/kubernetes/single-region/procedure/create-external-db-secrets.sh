# create a secret to reference external database credentials if you use it
kubectl create secret generic identity-keycloak-secret \
  --namespace camunda \
  --from-literal=host="$DB_HOST" \
  --from-literal=user="$DB_KEYCLOAK_USERNAME" \
  --from-literal=password="$DB_KEYCLOAK_PASSWORD" \
  --from-literal=database="$DB_KEYCLOAK_NAME" \
  --from-literal=port=5432

# create a secret to reference external Postgres for each component of Camunda 8
kubectl create secret generic identity-postgres-secret \
  --namespace camunda \
  --from-literal=password="$DB_IDENTITY_PASSWORD"

kubectl create secret generic webmodeler-postgres-secret \
  --namespace camunda \
  --from-literal=password="$DB_WEBMODELER_PASSWORD"

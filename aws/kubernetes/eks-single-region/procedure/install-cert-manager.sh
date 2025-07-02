#!/bin/bash

NAMESPACE="external-secrets"
SERVICE_ACCOUNT_NAME="external-secrets"
CLUSTER_SECRET_STORE_NAME="aws-secrets-manager"

helm repo add external-secrets https://charts.external-secrets.io

helm install external-secrets \
   external-secrets/external-secrets \
    -n "$NAMESPACE" \
    --create-namespace \
    --set "serviceAccount.annotations.eks\.amazonaws\.com\/role-arn=$ESO_IRSA_ARN"

echo "Waiting for External Secrets Operator deployment to be ready..."

kubectl rollout status deployment/external-secrets -n "$NAMESPACE" --timeout=180s


echo "Applying ClusterSecretStore manifest..."

cat <<EOF | envsubst > /tmp/clustersecretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: $CLUSTER_SECRET_STORE_NAME
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      auth:
        jwt:
          serviceAccountRef:
            name: $SERVICE_ACCOUNT_NAME
            namespace: $NAMESPACE
EOF

kubectl apply -f /tmp/clustersecretstore.yaml

echo "External Secrets Operator installed and ClusterSecretStore applied."

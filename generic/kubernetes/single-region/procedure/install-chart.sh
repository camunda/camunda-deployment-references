#!/bin/bash

# TODO: added to create the secret

kubectl apply -f - --namespace "$CAMUNDA_NAMESPACE" <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: aws-pca-p12
spec:
  refreshPolicy: Periodic
  refreshInterval: 1h

  secretStoreRef:
    name: aws-store
    kind: ClusterSecretStore

  target:
    name: aws-pca-p12
    creationPolicy: Merge
  data:
    - secretKey: tls.crt
      remoteRef:
        key: certs/$CAMUNDA_DOMAIN/certificate
    - secretKey: tls.key
      remoteRef:
        key: certs/$CAMUNDA_DOMAIN/private-key
    - secretKey: tls-keystore-password
      remoteRef:
        key: certs/$CAMUNDA_DOMAIN/p12-password
    - secretKey: tls-truststore-password
      remoteRef:
        key: certs/$CAMUNDA_DOMAIN/p12-password
    - secretKey: keycloak.truststore.jks
      remoteRef:
        key: certs/$CAMUNDA_DOMAIN/certificate-p12
    - secretKey: keycloak.keystore.jks
      remoteRef:
        key: certs/$CAMUNDA_DOMAIN/certificate-p12
EOF

helm upgrade --install \
    "$CAMUNDA_RELEASE_NAME" oci://ghcr.io/camunda/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" --namespace "$CAMUNDA_NAMESPACE" \
    -f generated-values.yml

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install \
#   "$CAMUNDA_RELEASE_NAME" camunda-platform \
#   --repo https://helm.camunda.io \
#   --version "$CAMUNDA_HELM_CHART_VERSION" \
#   --namespace "$CAMUNDA_NAMESPACE" \
#   -f generated-values.yml

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
    name: aws-secrets-manager
    kind: ClusterSecretStore

  target:
    name: aws-pca-p12
  data:
    - secretKey: ca.crt
      remoteRef:
        key: certs/picsou86.camunda.ie-subroot-ca/certificate
    - secretKey: tls.crt
      remoteRef:
        key: certs/camunda.picsou86.camunda.ie/certificate
    - secretKey: tls.key
      remoteRef:
        key: certs/camunda.picsou86.camunda.ie/private-key
    - secretKey: certificate-p12
      remoteRef:
        key: certs/camunda.picsou86.camunda.ie/certificate-p12
        decodingStrategy: Auto
    - secretKey: tls-keystore-password
      remoteRef:
        key: certs/camunda.picsou86.camunda.ie/p12-password
    - secretKey: tls-truststore-password
      remoteRef:
        key: certs/camunda.picsou86.camunda.ie/p12-password
    - secretKey: keystore.jks
      remoteRef:
        key: certs/camunda.picsou86.camunda.ie/keystore-jks
        decodingStrategy: Auto
    - secretKey: truststore.jks
      remoteRef:
        key: certs/camunda.picsou86.camunda.ie/truststore-jks
        decodingStrategy: Auto
EOF

helm upgrade --install \
    "$CAMUNDA_RELEASE_NAME" camunda-platform --repo https://helm.camunda.io  \
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

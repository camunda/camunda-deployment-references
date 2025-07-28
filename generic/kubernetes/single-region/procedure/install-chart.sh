#!/bin/bash

# TODO: added to create the secret

DOMAIN_BASE="picsou2.camunda.ie"

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
        key: certs/$DOMAIN_BASE-subroot-ca/certificate
    - secretKey: tls.crt
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/certificate
    - secretKey: tls.key
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/private-key
    - secretKey: certificate-p12
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/certificate-p12
        decodingStrategy: Auto
    - secretKey: tls-keystore-password
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/p12-password
    - secretKey: tls-truststore-password
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/p12-password
    - secretKey: keystore.jks
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/keystore-jks
        decodingStrategy: Auto
    - secretKey: truststore.jks
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/truststore-jks
        decodingStrategy: Auto

    - secretKey: keycloak.keystore.jks
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/keystore-jks
        decodingStrategy: Auto

    - secretKey: keycloak.truststore.jks
      remoteRef:
        key: certs/camunda.$DOMAIN_BASE/truststore-jks
        decodingStrategy: Auto
EOF

helm upgrade --install \
   "$CAMUNDA_RELEASE_NAME" camunda-platform --repo https://helm.camunda.io \
    --version "$CAMUNDA_HELM_CHART_VERSION" --namespace "$CAMUNDA_NAMESPACE" \
    -f generated-values.yml

# TODO: [release-duty] before the release, update this by removing the oci pull above
# and uncomment the installation instruction below

# helm upgrade --install \
#   "$CAMUNDA_RELEASE_NAME" camunda-platform --repo https://helm.camunda.io \
#   --version "$CAMUNDA_HELM_CHART_VERSION" \
#   --namespace "$CAMUNDA_NAMESPACE" \
#   -f generated-values.yml

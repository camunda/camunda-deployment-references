#!/bin/bash

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: "$MAIL"
    privateKeySecretRef:
      name: letsencrypt-issuer-account-key
    solvers:
      - dns01:
          azureDNS:
            resourceGroupName: "$AZURE_DNS_RESOURCE_GROUP"
            hostedZoneName: "$AZURE_DNS_ZONE"
            subscriptionID: "$AZURE_SUBSCRIPTION_ID"
            managedIdentity: {}
EOF

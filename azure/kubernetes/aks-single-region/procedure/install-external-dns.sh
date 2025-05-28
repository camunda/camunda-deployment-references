#!/bin/bash

helm upgrade --install \
  external-dns external-dns \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  --version "$EXTERNAL_DNS_HELM_CHART_VERSION" \
  --set provider=azure \
  --set txtOwnerId="${EXTERNAL_DNS_OWNER_ID:-external-dns}" \
  --set policy=sync \
  --set azure.resourceGroup="$AZURE_DNS_RESOURCE_GROUP" \
  --set azure.subscriptionId="$AZURE_SUBSCRIPTION_ID" \
  --set azure.useManagedIdentity=true \
  --namespace external-dns \
  --create-namespace

#!/bin/bash

helm upgrade --install \
  external-dns external-dns \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  --version "$EXTERNAL_DNS_HELM_CHART_VERSION" \
  --set provider=azure \
  --set txtOwnerId="${EXTERNAL_DNS_OWNER_ID:-external-dns}" \
  --set policy=sync \
  --set "extraArgs[0]=--azure-resource-group=rg-infraex-global-permanent" \
  --set "extraArgs[1]=--azure-subscription-id=5667840f-dd25-4fe1-99ee-5e752ec80b5c" \
  --set "extraArgs[2]=--azure-use-managed-identity=true" \
  --namespace external-dns \
  --create-namespace

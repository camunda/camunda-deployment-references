#!/bin/bash

helm upgrade --install \
  external-dns external-dns \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  --version "$EXTERNAL_DNS_HELM_CHART_VERSION" \
  --set provider=azure \
  --set txtOwnerId="${EXTERNAL_DNS_OWNER_ID:-external-dns}" \
  --set policy=sync \
  --namespace external-dns \
  --create-namespace

#! /bin/bash

helm upgrade --install \
  external-dns external-dns \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  --version "$EXTERNAL_DNS_HELM_CHART_VERSION" \
  --set "env[0].name=AWS_DEFAULT_REGION" \
  --set "env[0].value=$REGION" \
  --set txtOwnerId="${EXTERNAL_DNS_OWNER_ID:-external-dns}" \
  --set policy=sync \
  --set "serviceAccount.annotations.eks\.amazonaws\.com\/role-arn=$EXTERNAL_DNS_IRSA_ARN" \
  --namespace external-dns \
  --create-namespace

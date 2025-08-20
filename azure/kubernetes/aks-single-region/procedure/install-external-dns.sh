#!/bin/bash

helm upgrade --install external-dns external-dns \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  --version "$EXTERNAL_DNS_HELM_CHART_VERSION" \
  --namespace external-dns --create-namespace \
  --set provider.name=azure \
  --set policy=sync \
  --set txtOwnerId=external-dns-"$CLUSTER_NAME" \
  --set "extraVolumes[0].name=azure-config-file" \
  --set "extraVolumes[0].secret.secretName=azure-config-file" \
  --set "extraVolumeMounts[0].name=azure-config-file" \
  --set "extraVolumeMounts[0].mountPath=/etc/kubernetes" \
  --set "extraVolumeMounts[0].readOnly=true"

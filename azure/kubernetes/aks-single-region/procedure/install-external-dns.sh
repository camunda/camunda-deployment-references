#!/bin/bash

helm upgrade --install external-dns external-dns \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  --version "$EXTERNAL_DNS_HELM_CHART_VERSION" \
  --namespace external-dns --create-namespace \
  --set provider=azure \
  --set policy=sync \
  --set txtOwnerId=external-dns-camunda-470-rfo3h-aks-aks-single-region \
  --set azure.resourceGroup=rg-infraex-global-permanent \
  --set azure.subscriptionId=5667840f-dd25-4fe1-99ee-5e752ec80b5c \
  --set azure.useManagedIdentity=true \
  --set "extraArgs[0]=--azure-resource-group=rg-infraex-global-permanent" \
  --set "extraArgs[1]=--azure-subscription-id=5667840f-dd25-4fe1-99ee-5e752ec80b5c" \
  --set "extraArgs[2]=--azure-config-file=/etc/kubernetes/azure.json" \
  --set extraVolumes[0].name=azure-config-file \
  --set extraVolumes[0].secret.secretName=azure-config-file \
  --set extraVolumeMounts[0].name=azure-config-file \
  --set extraVolumeMounts[0].mountPath=/etc/kubernetes \
  --set extraVolumeMounts[0].readOnly=true

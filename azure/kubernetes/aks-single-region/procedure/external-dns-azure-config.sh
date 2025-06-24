#!/bin/bash

kubectl create namespace external-dns

kubectl -n external-dns create secret generic azure-config-file \
    --from-literal=azure.json="{
        \"subscriptionId\": \"$AZURE_SUBSCRIPTION_ID\",
        \"resourceGroup\": \"$AZURE_DNS_RESOURCE_GROUP\",
        \"useManagedIdentityExtension\": true
    }"

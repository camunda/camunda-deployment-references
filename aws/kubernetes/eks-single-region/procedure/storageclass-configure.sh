#!/bin/bash
kubectl patch storageclass default \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl apply -f ./manifests/storage-class.yml

#!/bin/bash
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl apply -f ./procedure/manifests/storage-class.yml

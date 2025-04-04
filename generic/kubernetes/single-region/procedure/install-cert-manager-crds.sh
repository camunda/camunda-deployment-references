#!/bin/bash

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/v$CERT_MANAGER_HELM_CHART_VERSION/cert-manager.crds.yaml"

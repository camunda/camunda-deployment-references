#!/bin/bash

set -euo pipefail

SC_NAME="premium-lrs-sc"

DEFAULTS=$(kubectl get storageclass -o json | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class"=="true") | .metadata.name')

if [ "$DEFAULTS" = "$SC_NAME" ]; then
    echo "OK: Only '$SC_NAME' is the default StorageClass."
    exit 0
fi

echo "FAIL: Default StorageClass is not set correctly."
echo "Current default(s): $DEFAULTS"
exit 1

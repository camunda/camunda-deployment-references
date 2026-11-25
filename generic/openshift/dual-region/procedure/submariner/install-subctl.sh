#!/bin/bash
set -euo pipefail

# Instructions from https://submariner.io/operations/deployment/subctl/
curl -Ls https://get.submariner.io -o submariner-install.sh

# Review the downloaded script
cat submariner-install.sh

SUBMARINER_CSV=$(oc --context "$CLUSTER_0" -n submariner-operator wait subscriptions.operators.coreos.com/submariner \
    --for=jsonpath='{.status.installedCSV}' --timeout=300s -o jsonpath='{.status.installedCSV}')
SUBCTL_VERSION=$(sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$/v\1/p' <<< "$SUBMARINER_CSV")
if [ -z "$SUBCTL_VERSION" ]; then
    echo "No Submariner version found in the installed CSV '$SUBMARINER_CSV' of the submariner Subscription in $CLUSTER_0." >&2
    exit 1
fi

VERSION="$SUBCTL_VERSION" bash submariner-install.sh
export PATH=$PATH:~/.local/bin
echo export PATH=\$PATH:~/.local/bin >> ~/.profile

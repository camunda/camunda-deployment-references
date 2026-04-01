#!/bin/bash
set -euo pipefail

oc --context "$CLUSTER_0" get mch -A
oc --context "$CLUSTER_0" apply -f managed-cluster-set.yml

#!/bin/bash
set -euo pipefail

envsubst < submariner.yml.tpl | oc --context "$CLUSTER_0" apply -f -

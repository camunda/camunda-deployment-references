#!/bin/bash
set -euo pipefail

oc --context "$CLUSTER_0" apply -f install-manifest.yml

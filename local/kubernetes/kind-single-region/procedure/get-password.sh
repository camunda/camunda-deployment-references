#!/bin/bash
set -euo pipefail

# Get Camunda admin password

kubectl get secret camunda-credentials -n camunda -o jsonpath='{.data.identity-first-user-password}' | base64 -d
echo

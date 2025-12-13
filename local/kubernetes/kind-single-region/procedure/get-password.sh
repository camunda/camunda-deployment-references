#!/bin/bash
set -euo pipefail

# Get Camunda admin password

kubectl get secret camunda-credentials -n camunda -o jsonpath='{.data.identity-firstuser-password}' | base64 -d
echo

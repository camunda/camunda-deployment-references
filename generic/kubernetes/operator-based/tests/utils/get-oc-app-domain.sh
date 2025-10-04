#!/bin/bash
set -euo pipefail

# Retrieve the OpenShift cluster apps domain
# This script gets the base domain used for applications on OpenShift
# The domain is used to configure ingress and routes for Camunda components

echo "Retrieving OpenShift apps domain..."

# Get the apps domain from the cluster ingress configuration
OPENSHIFT_APPS_DOMAIN="$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')"

if [[ -z "$OPENSHIFT_APPS_DOMAIN" ]]; then
    echo "Error: Unable to retrieve OpenShift apps domain" >&2
    exit 1
fi

echo "OpenShift apps domain: $OPENSHIFT_APPS_DOMAIN"

# Export the domain for use in other scripts
export OPENSHIFT_APPS_DOMAIN
echo "OPENSHIFT_APPS_DOMAIN=$OPENSHIFT_APPS_DOMAIN"

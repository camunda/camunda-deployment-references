#!/bin/bash

OPENSHIFT_APPS_DOMAIN="$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')"
export DOMAIN_NAME="camunda.$OPENSHIFT_APPS_DOMAIN"

echo "Camunda 8 will be reachable from $DOMAIN_NAME"

#!/bin/bash

OPENSHIFT_APPS_DOMAIN="$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')"
export CAMUNDA_DOMAIN="camunda.$OPENSHIFT_APPS_DOMAIN"

echo "Camunda 8 will be reachable from $CAMUNDA_DOMAIN"

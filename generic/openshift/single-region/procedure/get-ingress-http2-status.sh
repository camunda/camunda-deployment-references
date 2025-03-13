#!/bin/bash

# List your IngressControllers
oc -n openshift-ingress-operator get ingresscontrollers

# Replace OC_INGRESS_CONTROLLER_NAME with your IngressController name from the previous command
export OC_INGRESS_CONTROLLER_NAME=default
oc -n openshift-ingress-operator get "ingresscontrollers/$OC_INGRESS_CONTROLLER_NAME" -o json | jq '.metadata.annotations."ingress.operator.openshift.io/default-enable-http2"'

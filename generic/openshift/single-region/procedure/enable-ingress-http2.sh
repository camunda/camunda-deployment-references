#!/bin/bash

oc -n openshift-ingress-operator annotate "ingresscontrollers/$OC_INGRESS_CONTROLLER_NAME" ingress.operator.openshift.io/default-enable-http2=true

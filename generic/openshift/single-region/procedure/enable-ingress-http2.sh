#!/bin/bash
set -euo pipefail

oc -n openshift-ingress-operator annotate "ingresscontrollers/$OC_INGRESS_CONTROLLER_NAME" ingress.operator.openshift.io/default-enable-http2=true

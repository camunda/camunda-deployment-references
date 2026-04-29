#!/bin/bash
set -euo pipefail

# Enable HTTP/2 (ALPN h2) negotiation at the OpenShift router so gRPC clients
# can talk to Routes (e.g. Zeebe gateway) over reencrypt/edge TLS.
#
# Annotate the target IngressController to enable HTTP/2, then trigger a
# router rollout so haproxy reloads with the new config before tests run.
#
# NOTE: We deliberately do NOT annotate `ingresses.config/cluster`: ROSA
# managed clusters block that mutation via the
# "ingress-config-validation.managed.openshift.io" admission webhook
# ("Only privileged service accounts may access").
oc -n openshift-ingress-operator annotate --overwrite \
    "ingresscontrollers/$OC_INGRESS_CONTROLLER_NAME" \
    ingress.operator.openshift.io/default-enable-http2=true

# Force the router pods to roll out so they reload haproxy with HTTP/2 enabled.
ROUTER_DEPLOY=$(oc -n openshift-ingress get deploy -o name \
    | grep -E "router-${OC_INGRESS_CONTROLLER_NAME}$" | head -n1 || true)
if [[ -n "$ROUTER_DEPLOY" ]]; then
    oc -n openshift-ingress rollout restart "$ROUTER_DEPLOY"
    oc -n openshift-ingress rollout status "$ROUTER_DEPLOY" --timeout=5m
fi

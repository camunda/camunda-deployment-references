#!/bin/bash
set -euo pipefail

# Enable HTTP/2 (ALPN h2) negotiation at the OpenShift router so gRPC clients
# can talk to Routes (e.g. Zeebe gateway) over reencrypt/edge TLS.
#
# We set the annotation on BOTH the cluster Ingress config and the target
# IngressController to maximise compatibility across OCP variants (classic,
# ROSA, ROSA HCP), then trigger a rollout of the router deployment so the
# new haproxy config is picked up before tests run.
oc annotate --overwrite ingresses.config/cluster \
    ingress.operator.openshift.io/default-enable-http2=true
oc -n openshift-ingress-operator annotate --overwrite \
    "ingresscontrollers/$OC_INGRESS_CONTROLLER_NAME" \
    ingress.operator.openshift.io/default-enable-http2=true

# Force the router pods to roll out so they reload haproxy with HTTP/2 enabled.
# On ROSA HCP the router deployment is named `router-default`; tolerate other
# layouts by listing deployments matching the IngressController name.
ROUTER_DEPLOY=$(oc -n openshift-ingress get deploy -o name \
    | grep -E "router-${OC_INGRESS_CONTROLLER_NAME}$" | head -n1 || true)
if [[ -n "$ROUTER_DEPLOY" ]]; then
    oc -n openshift-ingress rollout restart "$ROUTER_DEPLOY"
    oc -n openshift-ingress rollout status "$ROUTER_DEPLOY" --timeout=5m
fi

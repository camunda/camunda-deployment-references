#!/bin/bash
set -euo pipefail

# Enable HTTP/2 (ALPN h2) on the OpenShift router so gRPC clients (e.g. the
# Zeebe gateway) can use Routes over reencrypt/edge TLS. Sets both the
# IngressController-level annotation and (best-effort) the cluster-wide
# annotation.
#
# On ROSA HCP managed clusters the cluster-wide annotation is denied by the
# admission webhook, and the IngressController-level annotation alone does
# NOT make HAProxy advertise ALPN h2 on the default cert path. An explicit
# per-Route certificate is required — see `copy-router-tls-secret.sh` and
# the OpenShift / ROSA HCP HTTP/2 section in camunda-docs.
oc -n openshift-ingress-operator annotate --overwrite \
    "ingresscontrollers/$OC_INGRESS_CONTROLLER_NAME" \
    ingress.operator.openshift.io/default-enable-http2=true

# Cluster-wide flag — best effort. If the managed admission webhook denies it
# (typical on ROSA HCP) we keep going with only the IngressController-level
# annotation, which is enough on most ROSA HCP setups.
if ! oc annotate --overwrite ingresses.config/cluster \
    ingress.operator.openshift.io/default-enable-http2=true 2>/tmp/http2-cluster-anno.err; then
    echo "⚠️  Could not set cluster-wide HTTP/2 annotation (often denied by ROSA managed webhook):"
    sed 's/^/    /' /tmp/http2-cluster-anno.err || true
    echo "   Continuing with IngressController-level annotation only."
fi

# Force the router pods to roll out so they reload haproxy with HTTP/2 enabled.
ROUTER_DEPLOY=$(oc -n openshift-ingress get deploy -o name \
    | grep -E "router-${OC_INGRESS_CONTROLLER_NAME}$" | head -n1 || true)
if [[ -n "$ROUTER_DEPLOY" ]]; then
    oc -n openshift-ingress rollout restart "$ROUTER_DEPLOY"
    oc -n openshift-ingress rollout status "$ROUTER_DEPLOY" --timeout=5m
fi

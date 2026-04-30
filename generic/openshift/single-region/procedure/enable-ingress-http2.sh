#!/bin/bash
set -euo pipefail

# Enable HTTP/2 (ALPN h2) negotiation at the OpenShift router so gRPC clients
# can talk to Routes (e.g. Zeebe gateway) over reencrypt/edge TLS.
#
# OpenShift exposes two annotations to enable HTTP/2:
#   1. cluster-wide via `ingresses.config/cluster`
#   2. per IngressController via `ingresscontrollers/<name>`
# In practice the IngressController-level annotation alone does not always
# advertise h2 in the front-end ALPN list — the cluster-wide flag is what
# actually flips `ROUTER_DISABLE_HTTP2=false` in haproxy. We set both, but
# tolerate webhook denial on the cluster-wide one (ROSA managed clusters
# block direct mutation of `ingresses.config/cluster` via the
# "ingress-config-validation.managed.openshift.io" admission webhook).
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

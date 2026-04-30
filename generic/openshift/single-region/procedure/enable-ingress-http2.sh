#!/bin/bash
set -euo pipefail

# TODO(docs): before merging, port the explanation block below into
# camunda-docs (Self-Managed > OpenShift > Ingress / ROSA HCP ALPN h2
# procedure). See companion script `copy-router-tls-secret.sh`.
#
# Enable HTTP/2 (ALPN h2) negotiation at the OpenShift router so gRPC clients
# can talk to Routes (e.g. Zeebe gateway) over reencrypt/edge TLS.
#
# OpenShift exposes two annotations to enable HTTP/2:
#   1. cluster-wide via `ingresses.config/cluster`
#   2. per IngressController via `ingresscontrollers/<name>`
#
# On self-managed OCP the cluster-wide annotation flips
# `ROUTER_DISABLE_HTTP2=false` AND makes HAProxy advertise ALPN on its default
# certificate path. We set both annotations.
#
# On ROSA HCP managed clusters the cluster-wide annotation is denied by the
# `ingress-config-validation.managed.openshift.io` admission webhook and the
# IngressController-level annotation, while accepted, does NOT cause HAProxy
# to advertise ALPN on the default frontend bind (the upstream HAProxy
# template emits `no-alpn` unconditionally on `fe_sni`/`fe_no_sni`). On those
# clusters, ALPN h2 is only enabled per-SNI via an entry in HAProxy's
# `crt-list`, which is generated only for Routes carrying an explicit
# `spec.tls.certificate`. The companion `copy-router-tls-secret.sh` script
# copies the router default wildcard cert into the Camunda namespace so the
# orchestration gRPC Route can reference it via `tls.secretName`.
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

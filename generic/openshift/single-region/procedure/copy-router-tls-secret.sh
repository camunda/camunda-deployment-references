#!/bin/bash
set -euo pipefail

# TODO(docs): before merging, port the explanation block below into
# camunda-docs (Self-Managed > OpenShift > Ingress / ROSA HCP ALPN h2
# procedure). See companion script `enable-ingress-http2.sh` and the
# `secretName` comment in `helm-values/orchestration-route.yml`.
#
# Copy the OpenShift router default wildcard TLS secret into the Camunda
# namespace so that the orchestration gRPC Route can reference it via
# `tls.secretName`. Without this, the Route falls back to the cluster
# wildcard cert *served implicitly* by HAProxy, which on ROSA HCP managed
# clusters never advertises ALPN h2 because the per-SNI `[alpn h2,http/1.1]`
# entry in HAProxy's `crt-list` is only generated when the Route carries an
# explicit `spec.tls.certificate`.
#
# Required env:
#   CAMUNDA_NAMESPACE                   target namespace (e.g. "camunda")
#   CAMUNDA_PLATFORM_ROUTER_TLS_SECRET  destination secret name
#                                       (default: camunda-platform-router-tls)
#
# The source secret is auto-discovered from the `default` IngressController
# `.spec.defaultCertificate.name` (falls back to the conventional
# `<infra-id>-primary-cert-bundle-secret` on ROSA HCP).

: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE is required}"
DEST_SECRET="${CAMUNDA_PLATFORM_ROUTER_TLS_SECRET:-camunda-platform-router-tls}"

SRC_SECRET="$(oc -n openshift-ingress-operator get ingresscontroller default \
    -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null || true)"

if [[ -z "$SRC_SECRET" ]]; then
    # ROSA HCP convention when defaultCertificate is not explicitly set on the IC.
    SRC_SECRET="$(oc -n openshift-ingress get secret -o name \
        | grep -E 'primary-cert-bundle-secret$' | head -n1 | sed 's|^secret/||')"
fi

if [[ -z "$SRC_SECRET" ]]; then
    echo "❌ Could not locate the router default TLS secret in openshift-ingress." >&2
    exit 1
fi

echo "ℹ️  Copying router TLS secret openshift-ingress/$SRC_SECRET → $CAMUNDA_NAMESPACE/$DEST_SECRET"

oc -n openshift-ingress get secret "$SRC_SECRET" -o json \
    | jq --arg ns "$CAMUNDA_NAMESPACE" --arg name "$DEST_SECRET" '
        .metadata = {name: $name, namespace: $ns}
        | .type = "kubernetes.io/tls"
      ' \
    | oc apply -f -

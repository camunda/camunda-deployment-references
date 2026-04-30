#!/bin/bash
set -euo pipefail

# Copy the OpenShift router default wildcard TLS secret into the Camunda
# namespace so the orchestration gRPC Route can reference it via
# `tls.secretName`. Required on ROSA HCP to make HAProxy advertise ALPN h2
# (per-SNI `crt-list` mechanism). See the OpenShift / ROSA HCP HTTP/2
# section in camunda-docs for the rationale.
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

#!/bin/bash

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" camunda-platform \
   --repo https://helm.camunda.io \
   --version "$CAMUNDA_HELM_CHART_VERSION" \
   --namespace "$CAMUNDA_NAMESPACE" \
   -f generated-values.yml

# Domain + OIDC mode only: the app pods (orchestration, Connectors) fetch the OIDC
# discovery document from the public Keycloak issuer at startup and CrashLoopBackOff
# until it converges (realm provisioning + DNS + TLS cert + ingress) — which can
# outlast their restart backoff. Wait (bounded, fail-open) for the issuer, then clear
# the backoff. Skipped when CAMUNDA_DOMAIN is unset (no public issuer, e.g. no-domain).
if [ -n "${CAMUNDA_DOMAIN:-}" ]; then
    "$(dirname "$0")/wait-for-keycloak.sh"
fi

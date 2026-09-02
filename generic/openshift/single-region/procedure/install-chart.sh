#!/bin/bash
set -euo pipefail

# Warn that this deploys an unreleased, in-development chart (to stderr).
# TODO: [release-duty] remove this pre-release warning at release.
cat >&2 <<'PRERELEASE_WARNING'

  ############################################################################
  #  ⚠  PRE-RELEASE — NOT A STABLE CAMUNDA RELEASE                           #
  #                                                                          #
  #  This deploys an unreleased, in-development Camunda 8 chart.             #
  #  It may be unstable or fail to start — that is expected here.            #
  #                                                                          #
  #  Need a stable, supported setup? Follow the Administrator quickstart:    #
  #  https://docs.camunda.io/docs/self-managed/quickstart/administrator-quickstart/
  ############################################################################

PRERELEASE_WARNING

# Build the chart from source so no registry authentication is required; prints the
# local chart directory. The build helper is shared with the generic k8s guide.
_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LOCAL_CHART="$("$_repo_root/generic/kubernetes/single-region/procedure/build-camunda-chart.sh")"

helm upgrade --install \
    "$CAMUNDA_RELEASE_NAME" "$LOCAL_CHART" \
    --namespace "$CAMUNDA_NAMESPACE" \
    -f generated-values.yml

# TODO: [release-duty] before the release, remove the source-build above and
# uncomment the standard Helm install below.

# helm upgrade --install \
#   "$CAMUNDA_RELEASE_NAME" camunda-platform \
#   --repo https://helm.camunda.io \
#   --version "$CAMUNDA_HELM_CHART_VERSION" \
#   --namespace "$CAMUNDA_NAMESPACE" \
#   -f generated-values.yml

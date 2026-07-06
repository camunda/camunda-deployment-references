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

# --force-update keeps this idempotent under `set -e` if the repo already exists.
helm repo add camunda https://helm.camunda.io --force-update
helm repo update

# Build the chart from source so no registry authentication is required; prints the
# local chart directory. The build helper is shared with the generic k8s guide.
_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LOCAL_CHART="$("$_repo_root/generic/kubernetes/single-region/procedure/build-camunda-chart.sh")"

# Resolve the broker image of the chart being installed so the cross-region
# DNS-gate initContainer (see helm-values/values-base.yml) reuses the exact
# same image as the broker — already pulled on the node, no extra pull, and no
# hardcoded tag to maintain. The generated values carry a literal ${BROKER_IMAGE}
# placeholder (passed through the first envsubst via ${DOLLAR}); resolve it here.
# yq is required for this; fail fast with a clear message instead of a generic
# "command not found" in the middle of the install flow.
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: 'yq' is required to resolve the broker image for the cross-region DNS gate but was not found in PATH." >&2
  exit 1
fi
# TODO: [release-duty] before the release, resolve the broker image from the public
# chart `camunda/camunda-platform` instead of the source-built chart, consistent with
# the install commands at the bottom of this file.
BROKER_IMAGE="$(helm show values "$LOCAL_CHART" \
  | yq -r '(.orchestration.image // .zeebe.image) | ([.registry, .repository] | map(. // "") | map(select(. != "")) | join("/")) + ":" + .tag')"
# Guard against a malformed result (e.g. unexpected chart values shape) so we never
# substitute an invalid image into the generated values and fail later with a confusing
# Helm/Kubernetes error. Require a non-empty repository AND a non-empty, non-"null" tag
# separated by a ':' — this rejects ":tag" (empty repo), "repo:" / "repo:null" and a
# value with no ':' at all.
broker_image_repo="${BROKER_IMAGE%:*}"
broker_image_tag="${BROKER_IMAGE##*:}"
if [ -z "$BROKER_IMAGE" ] || [ "$BROKER_IMAGE" = "$broker_image_tag" ] \
  || [ -z "$broker_image_repo" ] || [ -z "$broker_image_tag" ] || [ "$broker_image_tag" = "null" ]; then
  echo "ERROR: failed to resolve a valid broker image (registry/repository:tag) from the chart values (got '$BROKER_IMAGE')." >&2
  exit 1
fi
export BROKER_IMAGE
echo "Cross-region DNS-gate initContainer will reuse broker image: $BROKER_IMAGE"

for region_values in generated-values-region-0.yml generated-values-region-1.yml; do
  # Single quotes are envsubst's SHELL-FORMAT (only ${BROKER_IMAGE} is replaced),
  # not a shell expansion — leave everything else in the file untouched.
  # shellcheck disable=SC2016
  envsubst '${BROKER_IMAGE}' <"$region_values" >"$region_values.tmp"
  mv "$region_values.tmp" "$region_values"
done

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" "$LOCAL_CHART" \
  --kube-context "$CLUSTER_0" \
  --namespace "$CAMUNDA_NAMESPACE_0" \
  -f generated-values-region-0.yml

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" "$LOCAL_CHART" \
  --kube-context "$CLUSTER_1" \
  --namespace "$CAMUNDA_NAMESPACE_1" \
  -f generated-values-region-1.yml

# TODO: [release-duty] before the release, remove the source-build above and
# uncomment the installation instruction below

# helm upgrade --install \
#    "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
#   --version "$HELM_CHART_VERSION" \
#   --kube-context "$CLUSTER_0" \
#   --namespace "$CAMUNDA_NAMESPACE_0" \
#   -f generated-values-region-0.yml

# helm upgrade --install \
#   "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
#   --version "$HELM_CHART_VERSION" \
#   --kube-context "$CLUSTER_1" \
#   --namespace "$CAMUNDA_NAMESPACE_1" \
#   -f generated-values-region-1.yml

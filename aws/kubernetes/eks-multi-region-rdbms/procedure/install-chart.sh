#!/bin/bash
set -euo pipefail

# Installs or upgrades the Camunda chart in every active region.
#
# Optional first argument: a single region slot, used by activate-region.sh when
# a new region joins a running cluster.
#
# Expects the per-region values files produced by assemble-envsubst-values.sh in
# the current directory.

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

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"

# yq is required below to resolve the broker image for the cross-region DNS gate.
# Check it up front so we fail fast with a clear message before the network-heavy
# chart source-build, instead of a generic "command not found" mid-install.
if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: 'yq' is required to resolve the broker image for the cross-region DNS gate but was not found in PATH." >&2
    exit 1
fi

# Build the chart from source so no registry authentication is required; prints
# the local chart directory. The build helper is shared with the generic
# Kubernetes guide.
_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LOCAL_CHART="$("$_repo_root/generic/kubernetes/single-region/procedure/build-camunda-chart.sh")"

# Resolve the broker image of the chart being installed so the cross-region
# DNS-gate initContainer (see helm-values/camunda-values.yml) reuses the exact
# same image as the broker: already pulled on the node, no extra pull, and no
# hardcoded tag to maintain.
# TODO: [release-duty] resolve the broker image from the public chart
# `camunda/camunda-platform` instead of the source-built chart.
BROKER_IMAGE="$(helm show values "$LOCAL_CHART" |
    yq -r '(.orchestration.image // .zeebe.image) | ([.registry, .repository] | map(. // "") | map(select(. != "")) | join("/")) + ":" + .tag')"

# Fail fast when the values ask for zone awareness but the built chart cannot
# deliver it. Without this the chart silently ignores the unknown values, falls
# back to the legacy numbering, and every region numbers its brokers
# identically -- which surfaces ninety minutes later as brokers that cannot
# find each other, and reads like a networking problem.
_values_template="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helm-values" && pwd)/camunda-values.yml"
if grep -q "mode: zoned" "$_values_template" 2>/dev/null; then
    if ! grep -q "mode:" "$LOCAL_CHART/values.yaml" 2>/dev/null ||
        ! grep -q "zones:" "$LOCAL_CHART/values.yaml" 2>/dev/null; then
        echo "ERROR: the values request global.multiregion.mode=zoned, but the built chart does not support it." >&2
        echo "       Built from ref: ${CAMUNDA_HELM_CHART_GIT_REF:-<default pin in build-camunda-chart.sh>}" >&2
        echo "       Set CAMUNDA_HELM_CHART_GIT_REF to a ref carrying zoned mode; see camunda/camunda-platform-helm#6949." >&2
        exit 1
    fi
fi

broker_image_repo="${BROKER_IMAGE%:*}"
broker_image_tag="${BROKER_IMAGE##*:}"
if [ -z "$BROKER_IMAGE" ] || [ "$BROKER_IMAGE" = "$broker_image_tag" ] ||
    [ -z "$broker_image_repo" ] || [ -z "$broker_image_tag" ] || [ "$broker_image_tag" = "null" ]; then
    echo "ERROR: failed to resolve a valid broker image (registry/repository:tag) from the chart values (got '$BROKER_IMAGE')." >&2
    exit 1
fi
export BROKER_IMAGE
echo "Cross-region DNS-gate initContainer will reuse broker image: $BROKER_IMAGE"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"

install_slot() {
    local slot="$1"
    local values="generated-values-region-${slot}.yml"

    if [ ! -f "$values" ]; then
        echo "ERROR: $values not found. Run assemble-envsubst-values.sh first." >&2
        exit 1
    fi

    # Single quotes are envsubst's SHELL-FORMAT (only ${BROKER_IMAGE} is
    # replaced), not a shell expansion: everything else stays untouched.
    # shellcheck disable=SC2016
    envsubst '${BROKER_IMAGE}' <"$values" >"$values.tmp"
    mv "$values.tmp" "$values"

    # Optional overlay applied after the generated values, e.g. the CI
    # credentials overlay that provisions a local user matching the basic-auth
    # credentials the tests authenticate with. Without it the chart keeps its
    # default user and every authenticated call returns 401.
    local extra_args=()
    if [ -n "${CAMUNDA_EXTRA_VALUES:-}" ]; then
        if [ ! -f "$CAMUNDA_EXTRA_VALUES" ]; then
            echo "ERROR: CAMUNDA_EXTRA_VALUES points at $CAMUNDA_EXTRA_VALUES, which does not exist." >&2
            exit 1
        fi
        echo "Applying the extra values overlay: $CAMUNDA_EXTRA_VALUES"
        extra_args=(-f "$CAMUNDA_EXTRA_VALUES")
    fi

    echo "Installing $CAMUNDA_RELEASE_NAME into ${contexts[$slot]}/$CAMUNDA_NAMESPACE (region slot $slot)"
    helm upgrade --install \
        "$CAMUNDA_RELEASE_NAME" "$LOCAL_CHART" \
        --kube-context "${contexts[$slot]}" \
        --namespace "$CAMUNDA_NAMESPACE" \
        -f "$values" "${extra_args[@]}"
}

if [ $# -ge 1 ]; then
    # Slots are installed in the order given, which is how activate-region.sh
    # brings the new region up before restarting the ones already running.
    for slot in "$@"; do
        install_slot "$slot"
    done
else
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        install_slot "$i"
    done
fi

# TODO: [release-duty] remove the source-build above and use the public chart:
#
#   helm repo add camunda https://helm.camunda.io --force-update
#   helm repo update
#   helm upgrade --install "$CAMUNDA_RELEASE_NAME" camunda/camunda-platform \
#     --version "$HELM_CHART_VERSION" \
#     --kube-context "${contexts[$slot]}" \
#     --namespace "$CAMUNDA_NAMESPACE" \
#     -f "generated-values-region-${slot}.yml"

#!/usr/bin/env bash
set -euo pipefail

# Installs or upgrades the Camunda chart in every active region.
#
# Optional first argument: a single region slot, used by activate-region.sh when
# a new region joins a running cluster.
#
# Expects the per-region values files produced by assemble-envsubst-values.sh in
# the current directory.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RELEASE_NAME:?CAMUNDA_RELEASE_NAME must be set, source export_environment_prerequisites.sh}"
: "${HELM_CHART_REF:?HELM_CHART_REF must be set, source export_environment_prerequisites.sh}"
: "${HELM_CHART_VERSION:?HELM_CHART_VERSION must be set, source export_environment_prerequisites.sh}"

# yq is required below to resolve the broker image for the cross-region DNS gate.
# Check it up front so we fail fast with a clear message before the network-heavy
# chart download, instead of a generic "command not found" mid-install.
if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: 'yq' is required to resolve the broker image for the cross-region DNS gate but was not found in PATH." >&2
    exit 1
fi

# Resolve the broker image of the chart being installed so the cross-region
# DNS-gate initContainer (see helm-values/camunda-values.yml) reuses the exact
# same image as the broker: already pulled on the node, no extra pull, and no
# hardcoded tag to maintain.
BROKER_IMAGE="$(helm show values camunda-platform --repo "$HELM_CHART_REF" --version "$HELM_CHART_VERSION" |
    yq -r '(.orchestration.image // .zeebe.image) | ([.registry, .repository] | map(. // "") | map(select(. != "")) | join("/")) + ":" + .tag')"

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
        "$CAMUNDA_RELEASE_NAME" camunda-platform \
        --repo "$HELM_CHART_REF" \
        --version "$HELM_CHART_VERSION" \
        --kube-context "${contexts[$slot]}" \
        --namespace "$CAMUNDA_NAMESPACE" \
        -f "$values" "${extra_args[@]}"
}

if [ $# -ge 1 ]; then
    install_slot "$1"
else
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        install_slot "$i"
    done
fi

#!/bin/bash
set -euo pipefail

# The values overlays are layered with `yq '. *+ load(...)'`, which *appends*
# arrays instead of replacing them. That append is wanted for `*.env` lists, but
# it means two overlays that each add an `extraConfiguration` entry for the same
# `file:` mount that file twice. Helm renders it happily; server-side apply then
# rejects the Deployment with `volumeMounts: duplicate entries for key
# [mountPath=...]`, which does not name the values file at fault. Fail here,
# where the message can.
assert_no_duplicate_extra_configuration() {
    local values_file=$1 duplicates
    if ! command -v yq >/dev/null 2>&1; then
        echo "ERROR: yq is required to check $values_file for duplicate extraConfiguration entries." >&2
        echo "       Install it (see .tool-versions) or run 'just install-tooling'." >&2
        return 1
    fi
    duplicates=$(yq -r \
        '[.. | select(kind == "map" and has("extraConfiguration")) | .extraConfiguration | .[].file] | .[]' \
        "$values_file" | sort | uniq -d)
    [[ -z "$duplicates" ]] && return 0

    echo "ERROR: $values_file mounts the same extraConfiguration file more than once:" >&2
    while IFS= read -r duplicate; do echo "  - $duplicate" >&2; done <<<"$duplicates"
    echo "       Each file may be contributed by only one values overlay." >&2
    return 1
}

# yq is required below to resolve the broker image for the cross-region DNS gate.
# Check it up front so we fail fast with a clear message before the network-heavy
# chart download, instead of a generic "command not found" mid-install.
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: 'yq' is required to resolve the broker image for the cross-region DNS gate but was not found in PATH." >&2
  exit 1
fi

# Resolve the broker image of the chart being installed so the cross-region
# DNS-gate initContainer (see helm-values/values-base.yml) reuses the exact
# same image as the broker — already pulled on the node, no extra pull, and no
# hardcoded tag to maintain. The generated values carry a literal ${BROKER_IMAGE}
# placeholder (passed through the first envsubst via ${DOLLAR}); resolve it here.
BROKER_IMAGE="$(helm show values camunda-platform --repo https://helm.camunda.io --version "$HELM_CHART_VERSION" \
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
  assert_no_duplicate_extra_configuration "$region_values"
done

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" camunda-platform \
  --repo https://helm.camunda.io \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_0" \
  --namespace "$CAMUNDA_NAMESPACE_0" \
  -f generated-values-region-0.yml

helm upgrade --install \
  "$CAMUNDA_RELEASE_NAME" camunda-platform \
  --repo https://helm.camunda.io \
  --version "$HELM_CHART_VERSION" \
  --kube-context "$CLUSTER_1" \
  --namespace "$CAMUNDA_NAMESPACE_1" \
  -f generated-values-region-1.yml

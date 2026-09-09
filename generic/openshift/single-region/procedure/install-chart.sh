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

assert_no_duplicate_extra_configuration generated-values.yml

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

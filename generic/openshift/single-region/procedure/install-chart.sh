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

assert_no_duplicate_extra_configuration generated-values.yml

helm upgrade --install \
    "$CAMUNDA_RELEASE_NAME" camunda-platform \
    --repo https://helm.camunda.io \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "$CAMUNDA_NAMESPACE" \
    -f generated-values.yml

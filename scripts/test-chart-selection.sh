#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mkdir -p debug
scratch="$(mktemp -d "$repo_root/debug/chart-selection.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

# Execute the actual selection blocks, without cloning or invoking Helm.
for reader in generic/kubernetes/single-region/procedure/build-camunda-chart.sh \
    local/kubernetes/kind-single-region/procedure/build-camunda-chart.sh \
    .github/actions/internal-multi-region-tests/action.yml; do
    selection=""
    collecting=false
    while IFS= read -r line; do
        case "$line" in
            *'# Select chart directory.') collecting=true; continue ;;
            *'# End chart selection.') break ;;
        esac
        if [[ "$collecting" == true ]]; then selection+="$line"$'\n'; fi
    done < "$reader"
    [[ -n "$selection" ]]
    selection+=$'\nprintf "%s\\n" "$_local_chart"'
    export _chart_checkout_dir="$scratch/checkout" _camunda_version=8.11
    mkdir -p "$_chart_checkout_dir/charts/camunda-platform-8.9" \
        "$_chart_checkout_dir/charts/camunda-platform-8.10" \
        "$_chart_checkout_dir/charts/camunda-platform-8.11" \
        "$_chart_checkout_dir/charts/camunda-platform-8.12"
    touch "$_chart_checkout_dir/charts/camunda-platform-8.99"
    chosen="$(bash -euo pipefail -c "$selection" 2>"$scratch/stderr")"
    [[ "$chosen" == "$_chart_checkout_dir/charts/camunda-platform-8.11" && ! -s "$scratch/stderr" ]]
    rm -rf -- "$_chart_checkout_dir/charts/camunda-platform-8.11" \
        "$_chart_checkout_dir/charts/camunda-platform-8.12"
    chosen="$(bash -euo pipefail -c "$selection" 2>"$scratch/stderr")"
    [[ "$chosen" == "$_chart_checkout_dir/charts/camunda-platform-8.10" ]]
    warning="$(<"$scratch/stderr")"
    [[ "$warning" == *camunda-platform-8.11* && "$warning" == *camunda-platform-8.10* ]]
    rm -rf -- "$_chart_checkout_dir/charts"
    if bash -euo pipefail -c "$selection" 2>"$scratch/stderr"; then
        printf 'FAIL: %s accepted missing charts\n' "$reader" >&2
        exit 1
    fi
    printf 'PASS: %s exact minor, version-sorted fallback, warning, missing charts\n' "$reader"
done

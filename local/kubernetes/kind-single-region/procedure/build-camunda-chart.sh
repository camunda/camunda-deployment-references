#!/bin/bash
set -euo pipefail

# Build the Camunda Helm chart from source (camunda/camunda-platform-helm) so the
# kind guide needs no registry auth during the pre-release phase. Meant to be
# sourced by camunda-deploy-*.sh; sets and exports LOCAL_CHART.
#
# TODO: [release-duty] delete this helper at release time — the guide then installs
# the published chart from https://helm.camunda.io.
#
# Optional overrides: CAMUNDA_HELM_CHART_GIT_URL, CAMUNDA_HELM_CHART_GIT_REF,
# CAMUNDA_HELM_CHART_CHECKOUT_DIR.

_chart_src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$_chart_src_dir/../../../.."
_camunda_version="$(cat "$_repo_root/.camunda-version")"

_chart_git_url="${CAMUNDA_HELM_CHART_GIT_URL:-https://github.com/camunda/camunda-platform-helm.git}"
_chart_git_ref="${CAMUNDA_HELM_CHART_GIT_REF:-main}"
_chart_checkout_dir="${CAMUNDA_HELM_CHART_CHECKOUT_DIR:-$_chart_src_dir/../.camunda-platform-helm}"

echo "Building Camunda Helm chart 'camunda-platform-$_camunda_version' from source (ref: $_chart_git_ref)..."
rm -rf "$_chart_checkout_dir"
git clone --depth 1 --branch "$_chart_git_ref" "$_chart_git_url" "$_chart_checkout_dir"

LOCAL_CHART="$_chart_checkout_dir/charts/camunda-platform-$_camunda_version"
if [[ ! -d "$LOCAL_CHART" ]]; then
    echo "ERROR: chart 'camunda-platform-$_camunda_version' not found on ref '$_chart_git_ref'." >&2
    echo "       Expected directory: $LOCAL_CHART" >&2
    exit 1
fi

helm dependency update "$LOCAL_CHART"

export LOCAL_CHART

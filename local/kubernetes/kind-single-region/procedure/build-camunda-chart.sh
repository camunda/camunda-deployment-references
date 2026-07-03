#!/bin/bash
set -euo pipefail

# Build the Camunda Helm chart from source (camunda/camunda-platform-helm) so the
# kind guide needs no registry auth during the pre-release phase. Prints the built
# chart directory on stdout; capture it with:
#   LOCAL_CHART="$(./procedure/build-camunda-chart.sh)"
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

# The checkout dir is overridable and is deleted+recreated below. Three safety rules:
#   1. require an absolute path (rejects relative values like '.' or '..'),
#   2. never allow the filesystem root, and
#   3. only ever delete a directory THIS script created — detected via a marker
#      file — so pointing the override at an existing directory never removes it.
# '--' also keeps a value starting with '-' from being read as a flag.
_clone_marker=".built-by-build-camunda-chart"
if [[ "$_chart_checkout_dir" != /* ]]; then
    echo "ERROR: CAMUNDA_HELM_CHART_CHECKOUT_DIR must be an absolute path, got: '$_chart_checkout_dir'" >&2
    exit 1
fi
# Reject the filesystem root outright (any number of trailing slashes), so rm -rf
# can never target '/' even if a stray marker file were present there.
_root_probe="$_chart_checkout_dir"
while [[ "$_root_probe" == */ ]]; do _root_probe="${_root_probe%/}"; done
if [[ -z "$_root_probe" ]]; then
    echo "ERROR: refusing to use the filesystem root as the checkout directory." >&2
    exit 1
fi
if [[ -e "$_chart_checkout_dir" && ! -f "$_chart_checkout_dir/$_clone_marker" ]]; then
    echo "ERROR: '$_chart_checkout_dir' already exists and was not created by this script; refusing to delete it." >&2
    exit 1
fi

# Progress goes to stderr so stdout carries only the chart path.
echo "Building Camunda Helm chart 'camunda-platform-$_camunda_version' from source (ref: $_chart_git_ref)..." >&2
rm -rf -- "$_chart_checkout_dir"
git clone --depth 1 --branch "$_chart_git_ref" -- "$_chart_git_url" "$_chart_checkout_dir" >&2
touch "$_chart_checkout_dir/$_clone_marker"

_local_chart="$_chart_checkout_dir/charts/camunda-platform-$_camunda_version"
if [[ ! -d "$_local_chart" ]]; then
    echo "ERROR: chart 'camunda-platform-$_camunda_version' not found on ref '$_chart_git_ref'." >&2
    echo "       Expected directory: $_local_chart" >&2
    exit 1
fi

# Resolve the file:// "common" dependency locally (no registry auth); logs to stderr.
helm dependency update "$_local_chart" >&2

echo "$_local_chart"

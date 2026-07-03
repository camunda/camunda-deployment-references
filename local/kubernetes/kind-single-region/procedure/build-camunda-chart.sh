#!/bin/bash
set -euo pipefail

# Build the Camunda Helm chart from its source repository.
#
# TODO: [release-duty] this whole helper is a pre-release workaround. Delete it at
# release time, once the deploy scripts switch to installing the published chart
# from https://helm.camunda.io (see the [release-duty] blocks in camunda-deploy-*.sh).
#
# Why: during the pre-release phase of a Camunda minor, the chart (e.g. 15.x for
# Camunda 8.10) is not yet published to a public Helm repository, and the dev
# build is only pushed to an internal OCI registry that requires authentication
# (registry.camunda.cloud). Building the chart directly from
# https://github.com/camunda/camunda-platform-helm keeps this guide usable by
# everyone with no registry login required.
#
# The chart's only dependency is the in-repo "common" library (referenced via a
# file:// path), so "helm dependency update" resolves everything from the clone
# without contacting any registry.
#
# Usage: this script is meant to be *sourced* by the camunda-deploy-*.sh
# scripts. It sets and exports LOCAL_CHART to the path of the built chart, ready
# to be passed to "helm upgrade --install <release> \"$LOCAL_CHART\"".
#
# Optional override knobs (env vars):
#   CAMUNDA_HELM_CHART_GIT_URL       source repo URL (default: upstream GitHub)
#   CAMUNDA_HELM_CHART_GIT_REF       branch or tag to build (default: main)
#   CAMUNDA_HELM_CHART_CHECKOUT_DIR  clone location (default: ../.camunda-platform-helm)

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

# Resolve the file:// "common" library dependency locally — no registry auth.
helm dependency update "$LOCAL_CHART"

export LOCAL_CHART

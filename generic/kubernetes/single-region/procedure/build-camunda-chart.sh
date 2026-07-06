#!/bin/bash
set -euo pipefail

# Build the Camunda Helm chart from source (camunda/camunda-platform-helm) so the
# reference architectures need no registry authentication during the pre-release
# phase. Prints the built chart directory on stdout; capture it with:
#   LOCAL_CHART="$(.../procedure/build-camunda-chart.sh)"
#
# Shared by the generic install scripts (kubernetes/openshift, single/dual region).
#
# TODO: [release-duty] delete this helper at release time — the guides then install
# the published chart from https://helm.camunda.io.
#
# Optional overrides (env vars):
#   CAMUNDA_HELM_CHART_GIT_URL       source repo URL
#   CAMUNDA_HELM_CHART_GIT_REF       branch or tag to build (passed to git clone --branch)
#   CAMUNDA_HELM_CHART_CHECKOUT_DIR  clone location; must be an absolute path

# Fail fast with a clear message if a required tool is missing.
for _tool in git helm; do
    if ! command -v "$_tool" >/dev/null 2>&1; then
        echo "ERROR: '$_tool' is required to build the Camunda chart from source but was not found in PATH." >&2
        exit 1
    fi
done

_chart_src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root computed relative to this script (generic/kubernetes/single-region/
# procedure), so the helper works even without a .git dir (e.g. a source archive).
_repo_root="$(cd "$_chart_src_dir/../../../.." && pwd)"
_camunda_version="$(cat "$_repo_root/.camunda-version")"

_chart_git_url="${CAMUNDA_HELM_CHART_GIT_URL:-https://github.com/camunda/camunda-platform-helm.git}"
# Pin to the released chart tag the guides target (the pre-release 15.x line), not a
# moving 'main': 'main' can be mid-migration and drop components (e.g. console when
# values move under camundaHub), which breaks the deployment tests.
# TODO: [release-duty] bump this tag alongside CAMUNDA_HELM_CHART_VERSION and the helm-values.
_chart_git_ref="${CAMUNDA_HELM_CHART_GIT_REF:-camunda-platform-8.10-15.0.0-alpha2}"
_default_checkout_dir="$_repo_root/.camunda-platform-helm"
_chart_checkout_dir="${CAMUNDA_HELM_CHART_CHECKOUT_DIR:-$_default_checkout_dir}"

# The checkout dir is overridable and is deleted+recreated below, so validate it
# before the rm -rf: it must be an absolute path, contain no '.'/'..' segments, and
# not be the filesystem root; and a pre-existing dir must carry our marker file, so
# we only ever delete a checkout this script created. '--' below also keeps a value
# starting with '-' from being read as a flag.
_clone_marker=".built-by-build-camunda-chart"
if [[ "$_chart_checkout_dir" != /* ]]; then
    echo "ERROR: CAMUNDA_HELM_CHART_CHECKOUT_DIR must be an absolute path, got: '$_chart_checkout_dir'" >&2
    exit 1
fi
case "/$_chart_checkout_dir/" in
    */../* | */./*)
        echo "ERROR: CAMUNDA_HELM_CHART_CHECKOUT_DIR must not contain '.' or '..' path segments: '$_chart_checkout_dir'" >&2
        exit 1
        ;;
esac
# Reject the filesystem root outright (any number of trailing slashes), so rm -rf
# can never target '/' even if a stray marker file were present there.
_root_probe="$_chart_checkout_dir"
while [[ "$_root_probe" == */ ]]; do _root_probe="${_root_probe%/}"; done
if [[ -z "$_root_probe" ]]; then
    echo "ERROR: refusing to use the filesystem root as the checkout directory." >&2
    exit 1
fi
# Use the trailing-slash-stripped form for every use below, so 'rm -rf' can never
# follow a symlink via a path that ends in '/'.
_chart_checkout_dir="$_root_probe"
if [[ -e "$_chart_checkout_dir" && ! -f "$_chart_checkout_dir/$_clone_marker" ]]; then
    echo "ERROR: '$_chart_checkout_dir' already exists and was not created by this script; refusing to delete it." >&2
    exit 1
fi

# On any exit or interrupt, remove a checkout that never got its marker (e.g. an
# interrupted clone), so a rerun is not blocked by the guard above. A completed
# build keeps its marker, so this never deletes a successful checkout.
trap 'if [[ -e "$_chart_checkout_dir" && ! -f "$_chart_checkout_dir/$_clone_marker" ]]; then rm -rf -- "$_chart_checkout_dir"; fi' EXIT

# Progress goes to stderr so stdout carries only the chart path.
echo "Building Camunda Helm chart 'camunda-platform-$_camunda_version' from source (ref: $_chart_git_ref)..." >&2
rm -rf -- "$_chart_checkout_dir"
if ! git clone --depth 1 --branch "$_chart_git_ref" -- "$_chart_git_url" "$_chart_checkout_dir" >&2; then
    # Remove the partial checkout so the marker guard does not block a rerun.
    rm -rf -- "$_chart_checkout_dir"
    echo "ERROR: failed to clone '$_chart_git_url' (ref '$_chart_git_ref')." >&2
    exit 1
fi
if ! touch "$_chart_checkout_dir/$_clone_marker"; then
    # Remove the partial checkout so the marker guard does not block a rerun.
    rm -rf -- "$_chart_checkout_dir"
    echo "ERROR: failed to write the marker file in '$_chart_checkout_dir'." >&2
    exit 1
fi

_local_chart="$_chart_checkout_dir/charts/camunda-platform-$_camunda_version"
if [[ ! -d "$_local_chart" ]]; then
    echo "ERROR: chart 'camunda-platform-$_camunda_version' not found on ref '$_chart_git_ref'." >&2
    echo "       Expected directory: $_local_chart" >&2
    exit 1
fi

# Resolve the file:// "common" dependency locally (no registry auth); logs to stderr.
helm dependency update "$_local_chart" >&2

echo "$_local_chart"

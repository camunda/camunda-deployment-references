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
# Optional overrides (env vars):
#   CAMUNDA_HELM_CHART_GIT_URL       source repo URL
#   CAMUNDA_HELM_CHART_GIT_REF       branch or tag to build (passed to git clone --branch)
#   CAMUNDA_HELM_CHART_CHECKOUT_DIR  clone location; must be an absolute path
#   CAMUNDA_PRERELEASE_ACK           set to 'true' (or pass --yes) to skip the prompt

# Loudly warn that this deploys an unreleased, in-development build (to stderr so
# it never pollutes the chart path printed on stdout).
cat >&2 <<'PRERELEASE_WARNING'

  ############################################################################
  #  ⚠  PRE-RELEASE — NOT A STABLE CAMUNDA RELEASE                           #
  #                                                                          #
  #  This builds and deploys an unreleased, in-development Camunda 8 chart.  #
  #  It may be unstable or fail to start — that is expected here.            #
  #                                                                          #
  #  Need a stable, supported setup? Follow the Administrator quickstart:    #
  #  https://docs.camunda.io/docs/self-managed/quickstart/administrator-quickstart/
  ############################################################################

PRERELEASE_WARNING

# Require acknowledging the pre-release warning above. Bypass with
# CAMUNDA_PRERELEASE_ACK=true or the --yes/-y flag; run interactively without
# either and it prompts for confirmation.
_prerelease_ack="${CAMUNDA_PRERELEASE_ACK:-}"
for _arg in "$@"; do
    case "$_arg" in --yes | -y) _prerelease_ack="true" ;; esac
done
if [[ "$_prerelease_ack" != "true" ]]; then
    if [[ -t 0 ]]; then
        printf 'Continue with this pre-release build? [y/N] ' >&2
        read -r _reply || _reply=""
        case "$_reply" in
            [yY] | [yY][eE][sS]) ;;
            *) echo "Aborted: pre-release build not acknowledged." >&2; exit 1 ;;
        esac
    else
        echo "Non-interactive: set CAMUNDA_PRERELEASE_ACK=true (or pass --yes) to acknowledge the pre-release build." >&2
        exit 1
    fi
fi

_chart_src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$_chart_src_dir/../../../.."
_camunda_version="$(cat "$_repo_root/.camunda-version")"

_chart_git_url="${CAMUNDA_HELM_CHART_GIT_URL:-https://github.com/camunda/camunda-platform-helm.git}"
# Pin to the released chart tag the guide targets (the pre-release 15.x line), not a
# moving 'main': 'main' can be mid-migration and drop components (e.g. console when
# values move under camundaHub) or ship an inconsistent set of component images,
# which breaks the deployment tests. Renovate bumps the pin below only once a newer
# 8.10 chart tag is *published* (not the moving 'main' tip); the default is split out
# on its own line so the '# renovate:' inline manager can parse it (the ${VAR:-...}
# override wrapper is not cleanly matchable). A camunda-platform-helm release tag carries
# the previous version in its Chart.yaml (tag N ships version N-1), so the built chart is
# one prerelease behind the tag name — intentional; it's the known-good set the tests validate.
# renovate: datasource=github-tags depName=camunda/camunda-platform-helm extractVersion=^camunda-platform-8\.10-(?<version>.+)$
_chart_default_git_ref="camunda-platform-8.10-15.0.0-alpha3"
# TODO: [release-duty] bump the 8.10 pin above as the 15.x line advances (keep in sync with CAMUNDA_HELM_CHART_VERSION and the helm-values).
_chart_git_ref="${CAMUNDA_HELM_CHART_GIT_REF:-$_chart_default_git_ref}"
_default_checkout_dir="$(cd "$_chart_src_dir/.." && pwd)/.camunda-platform-helm"
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

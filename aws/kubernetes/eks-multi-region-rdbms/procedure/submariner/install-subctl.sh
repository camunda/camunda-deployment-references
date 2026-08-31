#!/bin/bash
set -euo pipefail

# Installs the subctl CLI. Must be sourced so that the PATH change survives:
#
#   source ./install-subctl.sh
#
# Instructions from https://submariner.io/operations/deployment/subctl/

curl -Ls https://get.submariner.io -o submariner-install.sh
cat submariner-install.sh

# renovate: datasource=github-releases depName=submariner-io/subctl
SUBCTL_VERSION=0.24.0

VERSION="$SUBCTL_VERSION" bash submariner-install.sh

# `$HOME` rather than `~`: the tilde does expand after a colon in an assignment,
# but the rule is obscure enough that every reader has to look it up, and in the
# profile line below `~` would be expanded when the line is WRITTEN, baking this
# machine's home into a file meant to be read on any.
export PATH="$PATH:$HOME/.local/bin"
# shellcheck disable=SC2016 # deliberate: $PATH and $HOME must expand when the
# profile is read, not when this line is written into it.
profile_line='export PATH="$PATH:$HOME/.local/bin"'
# Appended once. Re-running this script is normal, and every extra copy makes
# the profile a little longer and PATH a little more repetitive.
if ! grep -qxF "$profile_line" "$HOME/.profile" 2>/dev/null; then
    echo "$profile_line" >>"$HOME/.profile"
fi

subctl version

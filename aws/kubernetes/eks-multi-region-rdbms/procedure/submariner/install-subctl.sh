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

export PATH=$PATH:~/.local/bin
echo export PATH=\$PATH:~/.local/bin >>~/.profile

subctl version

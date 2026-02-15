#!/bin/bash

# Instructions from https://submariner.io/operations/deployment/subctl/
curl -Ls https://get.submariner.io -o submariner-install.sh

# Review the downloaded script
cat submariner-install.sh

# renovate: datasource=github-releases depName=submariner-io/subctl
SUBCTL_VERSION=0.22.1

VERSION="$SUBCTL_VERSION" bash submariner-install.sh
export PATH=$PATH:~/.local/bin
echo export PATH=\$PATH:~/.local/bin >> ~/.profile

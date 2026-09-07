#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# One-shot deployment: renders the per-region values and installs the chart in
# every active region.
#
# Lets a non-interactive caller run the complete deployment without sourcing
# generate-zeebe-helm-values.sh in its own shell. To inspect each stage, run:
#
#   . ./generate-zeebe-helm-values.sh
#   ./assemble-envsubst-values.sh
#   ./install-chart.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/generate-zeebe-helm-values.sh"

"$SCRIPT_DIR/assemble-envsubst-values.sh"
"$SCRIPT_DIR/install-chart.sh" "$@"

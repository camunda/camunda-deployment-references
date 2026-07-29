#!/bin/bash
# Resolve sourced files relative to this script, not the caller working directory.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# One-shot deployment: renders the per-region values and installs the chart in
# every active region.
#
# Exists so that a non-interactive caller (CI, the Go tests) does not have to
# source generate-zeebe-helm-values.sh in its own shell. When following the
# documentation by hand, run the three steps individually instead:
#
#   . ./generate-zeebe-helm-values.sh
#   ./assemble-envsubst-values.sh
#   ./install-chart.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/generate-zeebe-helm-values.sh"

"$SCRIPT_DIR/assemble-envsubst-values.sh"
"$SCRIPT_DIR/install-chart.sh" "$@"

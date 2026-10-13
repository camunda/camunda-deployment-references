#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mkdir -p debug
scratch="$(mktemp -d "$repo_root/debug/chart-source-test.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin"

cat >"$scratch/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-C" && "$3" == "checkout" ]]; then
    mkdir -p "$2/charts/camunda-platform-$(cat "$TEST_REPO_ROOT/.camunda-chart-version")"
fi
GIT
cat >"$scratch/bin/helm" <<'HELM'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "dependency" && "$2" == "update" && -d "$3" ]]
HELM
chmod +x "$scratch/bin/git" "$scratch/bin/helm"
export PATH="$scratch/bin:$PATH"
export TEST_REPO_ROOT="$repo_root"
export CAMUNDA_PRERELEASE_ACK=true
export CAMUNDA_HELM_CHART_GIT_REF=0123456789abcdef0123456789abcdef01234567

for helper in generic/kubernetes/single-region/procedure/build-camunda-chart.sh \
    local/kubernetes/kind-single-region/procedure/build-camunda-chart.sh; do
    export CAMUNDA_HELM_CHART_CHECKOUT_DIR="$scratch/checkout"
    chart="$(bash "$helper")"
    [[ "$chart" == "$scratch/checkout/charts/camunda-platform-$(cat .camunda-chart-version)" ]]
done

printf 'PASS: source builds use the available chart minor, independent of the development target\n'

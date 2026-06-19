#!/usr/bin/env bash
# Run `terraform test` only in directories whose .tf or .tftest.hcl files have
# changed in the staged diff. Designed for use as a pre-commit hook entry.
#
# Behavior:
#   1. Find staged .tf and .tftest.hcl files via git diff --cached.
#   2. For each such file, walk up to find the nearest ancestor directory
#      that contains a tests/ subdirectory with at least one .tftest.hcl file.
#   3. Deduplicate, run `terraform init -backend=false` then `terraform test`
#      in each. Skip if no tests exist.
#
# Exits 0 if all touched test suites pass, or if nothing was touched.
# Exits non-zero on any test failure.
#
# Limitations:
#   - Touching a file in aws/modules/foo will run aws/modules/foo/tests, not
#     downstream consumers that might also break. Run `terraform test` directly
#     in the consumer state for that.

set -euo pipefail

# Collect staged terraform-related files (added, modified, or renamed).
mapfile -t STAGED < <(git diff --cached --name-only --diff-filter=ACMR -- '*.tf' '*.tftest.hcl' 2>/dev/null || true)

if [[ ${#STAGED[@]} -eq 0 ]]; then
    exit 0
fi

# For each staged file, walk up to find the nearest dir containing tests/*.tftest.hcl.
declare -A TEST_DIRS=()
for f in "${STAGED[@]}"; do
    dir=$(dirname "$f")
    while [[ "$dir" != "." && "$dir" != "/" ]]; do
        if compgen -G "$dir/tests/*.tftest.hcl" > /dev/null; then
            TEST_DIRS[$dir]=1
            break
        fi
        dir=$(dirname "$dir")
    done
done

if [[ ${#TEST_DIRS[@]} -eq 0 ]]; then
    exit 0
fi

fail=0
for dir in "${!TEST_DIRS[@]}"; do
    echo "[terraform test] running in $dir"
    if ! ( cd "$dir" && terraform init -input=false -backend=false -reconfigure > /dev/null && terraform test ); then
        fail=1
        echo "[terraform test] FAILED in $dir" >&2
    fi
done

exit "$fail"

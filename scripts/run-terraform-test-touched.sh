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
#
# Portability: this runs as a pre-commit hook on contributor machines, so it
# sticks to bash 3.2 features. macOS still ships bash 3.2 as /bin/bash, where
# `mapfile` and associative arrays (`declare -A`) do not exist; newline-delimited
# strings plus `sort -u` cover the same ground everywhere.

set -euo pipefail

# Collect staged terraform-related files (added, modified, or renamed).
STAGED=$(git diff --cached --name-only --diff-filter=ACMR -- '*.tf' '*.tftest.hcl' 2>/dev/null || true)

if [[ -z $STAGED ]]; then
    exit 0
fi

# For each staged file, walk up to find the nearest dir containing tests/*.tftest.hcl.
# Fed by a here-string rather than a pipe, so the loop body stays in this shell.
TEST_DIRS=""
while IFS= read -r f; do
    [[ -n $f ]] || continue
    dir=$(dirname "$f")
    while [[ "$dir" != "." && "$dir" != "/" ]]; do
        if compgen -G "$dir/tests/*.tftest.hcl" > /dev/null; then
            TEST_DIRS+="$dir"$'\n'
            break
        fi
        dir=$(dirname "$dir")
    done
done <<< "$STAGED"

# Deduplicate: `sort -u` stands in for the associative-array keys.
TEST_DIRS=$(printf '%s' "$TEST_DIRS" | sort -u)

if [[ -z $TEST_DIRS ]]; then
    exit 0
fi

fail=0
while IFS= read -r dir; do
    [[ -n $dir ]] || continue
    echo "[terraform test] running in $dir"
    if ! ( cd "$dir" && terraform init -input=false -backend=false -reconfigure > /dev/null && terraform test ); then
        fail=1
        echo "[terraform test] FAILED in $dir" >&2
    fi
done <<< "$TEST_DIRS"

exit "$fail"

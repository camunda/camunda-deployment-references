#!/usr/bin/env bash
# check-no-demo-credentials.sh
#
# Guard against re-introducing the hardcoded `demo:demo` Camunda admin
# credentials that caused incident INC-5340 (publicly reachable deployments
# booting with a working demo / demo admin login).
#
# It fails the build when one of the canonical credential patterns appears in
# a tracked file, outside the vendored sub-trees and documentation.
#
# Two legitimate cases are tolerated and skipped:
#   1. Full-line comments  (`#`, `##`, `//`) — explanatory notes are not
#      live credentials. The team intentionally keeps INC-5340 references.
#   2. Lines carrying the inline opt-out marker (see ALLOW_MARKER) — used by
#      the few guard messages that name the forbidden value on purpose.
#
# Usage: ./.lint/check-no-demo-credentials/check-no-demo-credentials.sh
# Exit:  0 = clean, 1 = at least one hardcoded credential found.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Canonical credential patterns (POSIX ERE). Mirrors the acceptance-criteria
# grep from camunda/team-infrastructure-experience#1111 so the check and the
# incident stay in lock-step.
PATTERN='demo:demo|demo/demo|USERNAME=demo|PASSWORD=demo|-u demo'

# Inline opt-out marker. Append it (as a trailing comment) to a line that names
# the forbidden value on purpose — e.g. an error message that refuses to fall
# back to it. Keep these rare and reviewed.
ALLOW_MARKER='no-demo-credentials:ignore'

# Paths excluded from the scan:
#   - vendored / sibling repos that ship their own history and policy
#   - markdown docs (illustrative prose, auto-generated action READMEs)
#   - this guard's own files (they necessarily contain the patterns above)
EXCLUDES=(
    ':!camunda-docs/'
    ':!camunda-platform-helm/'
    ':!infra-core/'
    ':!c8-sm-checks/'
    ':!*.md'
    ':!.lint/check-no-demo-credentials/'
)

# git grep exits 1 when there is no match; that is the success path here.
matches=()
while IFS= read -r line; do
    [ -n "$line" ] && matches+=("$line")
done < <(git grep -nIE "$PATTERN" -- "${EXCLUDES[@]}" 2>/dev/null || true)

violations=()
for line in "${matches[@]}"; do
    # git grep -n prints "path:lineno:content"; strip the first two fields.
    content="${line#*:}"
    content="${content#*:}"

    # 1. Explicit, reviewed opt-out.
    case "$content" in
        *"$ALLOW_MARKER"*) continue ;;
    esac

    # 2. Full-line comments (leading #, ##, // after optional indentation).
    trimmed="${content#"${content%%[![:space:]]*}"}"
    case "$trimmed" in
        '#'* | '//'*) continue ;;
    esac

    violations+=("$line")
done

if [ "${#violations[@]}" -gt 0 ]; then
    {
        echo "ERROR: hardcoded demo credentials detected (INC-5340)."
        echo
        printf '  %s\n' "${violations[@]}"
        echo
        echo "Fix: source the credential from configuration / Vault instead of"
        echo "hardcoding it. If the match is an intentional, non-credential mention"
        echo "(e.g. a guard message), append the marker '${ALLOW_MARKER}' to the line"
        echo "after review."
    } >&2
    exit 1
fi

echo "OK: no hardcoded demo credentials found."

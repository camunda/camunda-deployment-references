#!/bin/bash
set -euo pipefail

# Fails a pull request that does not update RELEASE-NOTES.md, unless it carries
# the `no-changelog` label or a bot opened it. Called by
# .github/workflows/internal_global_pr_changelog_check.yml.
#
# Usage:
#   changelog-check.sh check       # reads PR_USER_TYPE, PR_LABELS (JSON), PR_NUMBER, GITHUB_REPOSITORY
#   changelog-check.sh selftest

SKIP_LABEL="no-changelog"
NOTES="RELEASE-NOTES.md"

# <user type> <labels JSON array> <notes file present: true|false>, stdin:
# changed file paths. Prints `pass: <reason>` or `fail: <reason>`.
changelog_decision() {
    local user_type="$1" labels="$2" present="$3" files
    files=$(cat)
    if [[ "$present" != "true" ]]; then
        echo "pass: no ${NOTES} on the base branch"
    elif [[ "$user_type" == "Bot" ]]; then
        echo "pass: opened by a bot"
    elif jq -e --arg l "$SKIP_LABEL" 'index($l)' <<<"$labels" >/dev/null; then
        echo "pass: '${SKIP_LABEL}' label"
    elif grep -qxF "$NOTES" <<<"$files"; then
        echo "pass: ${NOTES} updated"
    else
        echo "fail: ${NOTES} not updated and no '${SKIP_LABEL}' label"
    fi
}

selftest() {
    local failures=0
    _expect() {
        local name="$1" got="$2" want="$3"
        if [[ "$got" == "$want" ]]; then
            echo "ok   $name"
        else
            echo "FAIL $name: got '$got' want '$want'"
            failures=$((failures + 1))
        fi
    }

    _expect "notes updated passes" \
        "$(printf 'aws/a.tf\nRELEASE-NOTES.md\n' | changelog_decision User '[]' true)" \
        "pass: ${NOTES} updated"
    _expect "notes not updated fails" \
        "$(printf 'aws/a.tf\n' | changelog_decision User '["bug"]' true)" \
        "fail: ${NOTES} not updated and no '${SKIP_LABEL}' label"
    _expect "a file only named like the notes does not count" \
        "$(printf 'docs/RELEASE-NOTES.md\n' | changelog_decision User '[]' true)" \
        "fail: ${NOTES} not updated and no '${SKIP_LABEL}' label"
    _expect "skip label passes" \
        "$(printf 'aws/a.tf\n' | changelog_decision User '["bug","no-changelog"]' true)" \
        "pass: '${SKIP_LABEL}' label"
    _expect "a longer label does not skip" \
        "$(printf 'aws/a.tf\n' | changelog_decision User '["no-changelog-please"]' true)" \
        "fail: ${NOTES} not updated and no '${SKIP_LABEL}' label"
    _expect "bot author passes" \
        "$(printf 'aws/a.tf\n' | changelog_decision Bot '[]' true)" \
        "pass: opened by a bot"
    _expect "branch without notes passes" \
        "$(printf 'aws/a.tf\n' | changelog_decision User '[]' false)" \
        "pass: no ${NOTES} on the base branch"
    _expect "empty diff fails" \
        "$(changelog_decision User '[]' true </dev/null)" \
        "fail: ${NOTES} not updated and no '${SKIP_LABEL}' label"

    echo "${failures} failure(s)"
    [[ "$failures" -eq 0 ]]
}

check() {
    local files decision present=false
    [[ -f "$NOTES" ]] && present=true
    files=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" --jq '.[].filename')
    decision=$(changelog_decision "$PR_USER_TYPE" "$PR_LABELS" "$present" <<<"$files")
    echo "$decision"
    if [[ "$decision" == fail:* ]]; then
        echo "::error::Add your user-visible change to the matching section of ${NOTES}, or add the '${SKIP_LABEL}' label if the change is not user-visible."
        return 1
    fi
}

case "${1:-}" in
    selftest) selftest ;;
    check) check ;;
    *) echo "usage: $0 check | selftest" >&2; exit 2 ;;
esac

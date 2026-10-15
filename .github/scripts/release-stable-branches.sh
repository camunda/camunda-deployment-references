#!/bin/bash
set -euo pipefail

# Publishes one GitHub Release per maintained `stable/8.x` branch when the
# branch's `## 8.x` section of RELEASE-NOTES.md changed since its last release.
# Called by .github/workflows/internal_global_release_stable_branches.yml.
# MAINTENANCE.md, "Release duty", step 12, documents the rules.
#
# Usage:
#   release-stable-branches.sh branches [renovate.json5]  # JSON list of maintained stable branches
#   release-stable-branches.sh release <stable/8.x>      # decide, then tag + release (DRY_RUN=true: decide only)
#   release-stable-branches.sh selftest

# --- pure functions (covered by selftest) ------------------------------------

maintained_branches() {
    # stdin: .github/renovate.json5. Quoted `stable/*` entries of the
    # `baseBranchPatterns` array; `//` comment lines are ignored.
    awk '
        /^[[:space:]]*baseBranchPatterns:[[:space:]]*\[/ { inside = 1; next }
        inside && /^[[:space:]]*\]/ { exit }
        inside && !/^[[:space:]]*\/\// { print }
    ' | grep -oE "[\"']stable/[0-9]+\.[0-9]+[\"']" | tr -d "\"'" | jq -Rnc '[inputs]'
}

extract_section() {
    # stdin: RELEASE-NOTES.md. Prints the `## <minor>` section (heading
    # included, optional suffix such as " (unreleased)" allowed) up to the
    # next `## ` heading, without trailing blank lines.
    local minor="$1"
    awk -v h="## ${minor}" '
        /^## / { if (inside) exit; inside = ($0 == h || index($0, h " ") == 1) }
        inside { print }
    ' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

section_changed() {
    # Exit 0 when the section changed. Whitespace is normalised so that a
    # reflow or a trailing newline does not publish a release.
    local previous="$1" current="$2"
    _norm() { tr -s '[:space:]' ' ' <<<"$1" | sed 's/^ //;s/ $//'; }
    [[ -z "$previous" ]] || [[ "$(_norm "$previous")" != "$(_norm "$current")" ]]
}

week_tag() {
    # <minor> [YYYY-MM-DD]: `<minor>-YYwWW` with the ISO week-year and week
    # (`date +%gw%V`). GNU date on runners, BSD date for local pre-commit.
    local minor="$1" day="${2:-}"
    if [[ -z "$day" ]]; then
        echo "${minor}-$(date -u +%gw%V)"
    else
        echo "${minor}-$(date -u -d "$day" +%gw%V 2>/dev/null || date -u -j -f %Y-%m-%d "$day" +%gw%V)"
    fi
}

next_free_tag() {
    # <prefix>, stdin: names already used by a tag or a release. Prints the
    # first `<prefix><a..z>` not in the list, fails when all are used.
    local prefix="$1" used letter
    used=$(cat)
    for letter in {a..z}; do
        if ! grep -qxF "${prefix}${letter}" <<<"$used"; then
            echo "${prefix}${letter}"
            return 0
        fi
    done
    echo "::error::every tag ${prefix}a..z is used" >&2
    return 1
}

is_latest() {
    # <minor> <JSON branch list>: "true" when <minor> is the highest
    # maintained minor, so only its release carries the Latest badge.
    local minor="$1" highest
    highest=$(jq -r '.[] | sub("^stable/"; "")' <<<"$2" | sort -V | tail -n 1)
    [[ "$minor" == "$highest" ]] && echo true || echo false
}

# --- selftest ----------------------------------------------------------------

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

    local renovate notes
    renovate=$(cat <<'EOF'
{
  packageRules: [{ matchBaseBranches: ['stable/8.7'] }],
  baseBranchPatterns: [
    'main',
    // TODO: [release-duty] remove 'stable/8.6' when its maintenance ends
    'stable/8.9',
    "stable/8.10",
  ]
}
EOF
)
    _expect "branches come from baseBranchPatterns only, comments ignored" \
        "$(maintained_branches <<<"$renovate")" '["stable/8.9","stable/8.10"]'

    notes=$(printf '%s\n' '# Notes' '' '## 8.11 (unreleased)' '' 'next' '' \
        '## 8.10' '' '### AWS' '' '- fix A' '' '## 8.1' '' '- old')
    _expect "section 8.10 stops at the next minor heading" \
        "$(extract_section 8.10 <<<"$notes")" "$(printf '%s\n' '## 8.10' '' '### AWS' '' '- fix A')"
    _expect "section 8.1 does not match 8.10 or 8.11" \
        "$(extract_section 8.1 <<<"$notes")" "$(printf '%s\n' '## 8.1' '' '- old')"
    _expect "a heading with a suffix still matches" \
        "$(extract_section 8.11 <<<"$notes")" "$(printf '%s\n' '## 8.11 (unreleased)' '' 'next')"
    _expect "a missing section is empty" "$(extract_section 8.9 <<<"$notes")" ""

    _expect "same text is unchanged" "$(section_changed $'a\nb' $'a\nb' && echo yes || echo no)" "no"
    _expect "whitespace-only edit is unchanged" \
        "$(section_changed $'- a  b\n\n' $'-   a b' && echo yes || echo no)" "no"
    _expect "new bullet is a change" "$(section_changed $'- a' $'- a\n- b' && echo yes || echo no)" "yes"
    _expect "no previous section is a change" "$(section_changed '' $'- a' && echo yes || echo no)" "yes"

    _expect "week tag uses ISO year and week" "$(week_tag 8.10 2026-10-15)" "8.10-26w42"
    _expect "ISO week-year differs from calendar year" "$(week_tag 8.10 2027-01-01)" "8.10-26w53"
    _expect "single-digit week is zero-padded" "$(week_tag 8.9 2026-01-05)" "8.9-26w02"

    _expect "first release of the week is a" "$(next_free_tag 8.10-26w42 <<<'')" "8.10-26w42a"
    _expect "a used gives b" "$(next_free_tag 8.10-26w42 <<<'8.10-26w42a')" "8.10-26w42b"
    _expect "used letters are skipped, gaps reused" \
        "$(next_free_tag 8.10-26w42 <<<$'8.10-26w42a\n8.10-26w42c\n8.9-26w42b')" "8.10-26w42b"
    _expect "all letters used fails" \
        "$(printf '8.1-26w42%s\n' {a..z} | { next_free_tag 8.1-26w42 2>/dev/null || echo exhausted; })" "exhausted"

    _expect "highest maintained minor is latest" "$(is_latest 8.10 '["stable/8.9","stable/8.10"]')" "true"
    _expect "lower minor is not latest" "$(is_latest 8.9 '["stable/8.9","stable/8.10"]')" "false"

    echo "${failures} failure(s)"
    [[ "$failures" -eq 0 ]]
}

# --- GitHub side -------------------------------------------------------------

release_branch() {
    local branch="$1"
    local repo="${GITHUB_REPOSITORY:-camunda/camunda-deployment-references}"
    local dry_run="${DRY_RUN:-true}"
    local renovate="${RENOVATE_CONFIG:-.github/renovate.json5}"
    local minor maintained head current releases tags last="" previous state
    local tag reuse=false tag_sha latest notes tag_object

    [[ "$branch" =~ ^stable/(8\.[0-9]+)$ ]] || { echo "::error::not a stable branch: ${branch}" >&2; return 1; }
    minor="${BASH_REMATCH[1]}"
    maintained=$(maintained_branches <"$renovate")
    if ! jq -e --arg b "$branch" 'index($b)' <<<"$maintained" >/dev/null; then
        echo "::error::${branch} is not in baseBranchPatterns of ${renovate}: ${maintained}" >&2
        return 1
    fi

    # The checkout (fetch-depth: 0) has every branch and tag; fetch again so a
    # local run sees the same state as the runner.
    git fetch --quiet --force --tags origin "+refs/heads/${branch}:refs/remotes/origin/${branch}"
    head=$(git rev-parse "origin/${branch}^{commit}")
    current=$(git show "${head}:RELEASE-NOTES.md" 2>/dev/null | extract_section "$minor" || true)
    echo "${branch}: head ${head}"
    if [[ -z "$current" ]]; then
        echo "::notice::${branch}: no '## ${minor}' section in RELEASE-NOTES.md, nothing to release."
        return 0
    fi

    # Baseline = newest *released* tag of this minor, by tag date. A tag left
    # without a release by a failed run is not a baseline: it is retried.
    local re="^${minor//./\\.}(-[0-9]{2}w[0-9]{2}[a-z]|\\.[0-9]+)$"
    releases=$(gh release list -R "$repo" --limit 1000 --json tagName --jq '.[].tagName' | grep -E "$re" || true)
    tags=$(gh api --paginate "repos/${repo}/git/matching-refs/tags/${minor}" --jq '.[].ref | ltrimstr("refs/tags/")' | grep -E "$re" || true)
    if [[ -n "$releases" ]]; then
        local -a release_refs=()
        local name
        while IFS= read -r name; do release_refs+=("refs/tags/${name}"); done <<<"$releases"
        last=$(git for-each-ref --sort=-creatordate --format='%(refname:short)' "${release_refs[@]}" | head -n 1)
    fi
    echo "${branch}: last release ${last:-none}"

    if [[ -n "$last" ]]; then
        previous=$(git show "${last}:RELEASE-NOTES.md" 2>/dev/null | extract_section "$minor" || true)
        if ! section_changed "$previous" "$current"; then
            echo "::notice::${branch}: '## ${minor}' unchanged since ${last}, no release."
            return 0
        fi
        if [[ "$(git rev-parse "${last}^{commit}")" == "$head" ]]; then
            echo "::notice::${branch}: head is already released as ${last}, no release."
            return 0
        fi
    fi

    # Legacy combined status only: GitHub Actions results are check runs and
    # are not part of it. A red nightly must not block every release.
    state=$(gh api "repos/${repo}/commits/${head}/status" --jq .state)
    if [[ "$state" == "failure" ]]; then
        echo "::warning::${branch}: combined status of ${head} is failure, no release."
        return 0
    fi

    tag=$(next_free_tag "$(week_tag "$minor")" <<<"$releases")
    if grep -qxF "$tag" <<<"$tags"; then
        tag_sha=$(git rev-parse "refs/tags/${tag}^{commit}")
        if [[ "$tag_sha" != "$head" ]]; then
            echo "::error::tag ${tag} exists without a release on ${tag_sha}, expected ${head}." >&2
            return 1
        fi
        reuse=true
    fi
    latest=$(is_latest "$minor" "$maintained")

    notes="${RUNNER_TEMP:-debug}/release-notes-${minor}.md"
    {
        echo "$current"
        if [[ -n "$last" ]]; then
            echo
            echo "**Full changelog**: https://github.com/${repo}/compare/${last}...${tag}"
        fi
    } >"$notes"

    echo "${branch}: release ${tag} on ${head} (reuse tag: ${reuse}, latest: ${latest}, dry run: ${dry_run})"
    echo "----- notes -----"
    cat "$notes"
    echo "-----------------"
    [[ "$dry_run" == "false" ]] || return 0

    if [[ "$reuse" == "false" ]]; then
        # Annotated, like the tags created by hand before this workflow.
        tag_object=$(gh api "repos/${repo}/git/tags" -f tag="$tag" -f object="$head" -f type=commit \
            -f message="Camunda Reference Architectures ${tag}" --jq .sha)
        gh api "repos/${repo}/git/refs" -f ref="refs/tags/${tag}" -f sha="$tag_object" >/dev/null
    fi
    gh release create "$tag" -R "$repo" --verify-tag --title "Camunda ${minor} (${tag})" \
        --notes-file "$notes" --latest="$latest"
}

case "${1:-}" in
    selftest) selftest ;;
    branches) maintained_branches <"${2:-.github/renovate.json5}" ;;
    release) release_branch "${2:?branch}" ;;
    *) echo "usage: $0 branches [file] | release <stable/8.x> | selftest" >&2; exit 2 ;;
esac

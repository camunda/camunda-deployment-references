#!/bin/bash
set -euo pipefail

# Decides whether the current workflow should skip, given the labels and the
# skip-checklist comment on a pull request. Prints `true` or `false`.
#
# Lives in a script rather than inline in action.yml because this is the part
# that got the answer wrong, and an inline `run:` block cannot be exercised
# from a pre-commit hook. See ghost_selftest in
# .github/actions/aws-generic-terraform-cleanup/scripts/ for the same shape.
#
# Usage:
#   SKIP_LABELS=$'label-a\nlabel-b' SKIP_CHECKLIST="$comment_body" \
#       skip-decision.sh <workflow_file_name_without_extension>
#   skip-decision.sh selftest

# skip_decision answers for one workflow name. Both inputs may be empty: a pull
# request can carry no labels, and the checklist comment is posted by a separate
# step that is allowed to fail without blocking the run.
skip_decision() {
    local workflow_name="$1" labels="${2-}" checklist="${3-}"
    local skip_label="skip_${workflow_name}"

    # Whole-line, fixed-string matching. The previous form was
    #   grep -qE "$skip_pattern|skip_all|testing-ci-not-necessary"
    # which matches on substrings, so a label naming one workflow also skipped
    # every workflow whose name is a prefix of it: the real case was
    # skip_local_kubernetes_kind_single_region_tests_e2e silently disabling
    # local_kubernetes_kind_single_region_tests. Unanchored also meant the
    # workflow name was interpolated into a regex, where a metacharacter in a
    # future filename would quietly change what matches.
    #
    # Here-string rather than `echo ... |`: under pipefail a `grep -q` that
    # matches early can kill the producer with SIGPIPE, and the pipeline then
    # reports 141 on a *successful* match -- running a workflow the label asked
    # to skip.
    if grep -qxF -e "$skip_label" -e "skip_all" -e "testing-ci-not-necessary" <<<"$labels"; then
        echo "[debug] skip directive found in the labels" >&2
        echo "true"
        return 0
    fi

    # A checked box in the checklist comment is the other way to ask for a skip.
    # Fixed strings again, one per accepted casing: the surrounding backticks
    # already stop a longer label from matching, but keeping it literal means the
    # label never has to be regex-escaped.
    local box
    for box in "$skip_label" "skip_all"; do
        if grep -qF -e "- [x] \`${box}\`" -e "- [X] \`${box}\`" <<<"$checklist"; then
            echo "[debug] \`${box}\` is checked in the checklist comment" >&2
            echo "true"
            return 0
        fi
    done

    echo "[debug] no skip directive for '${workflow_name}'" >&2
    echo "false"
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

    local kind="local_kubernetes_kind_single_region_tests"
    local longer="skip_local_kubernetes_kind_single_region_tests_e2e"

    _expect "an exact label skips" \
        "$(skip_decision "$kind" "skip_${kind}")" "true"

    # The regression this file exists for: the label names a different workflow,
    # and this one's name is merely a prefix of it.
    _expect "a longer label that contains the name does not skip" \
        "$(skip_decision "$kind" "$longer")" "false"

    _expect "an unrelated label does not skip" \
        "$(skip_decision "$kind" "skip_aws_compute_ec2_single_region_tests")" "false"

    _expect "no labels and no checklist does not skip" \
        "$(skip_decision "$kind")" "false"

    _expect "skip_all skips" \
        "$(skip_decision "$kind" "skip_all")" "true"

    _expect "testing-ci-not-necessary skips" \
        "$(skip_decision "$kind" "testing-ci-not-necessary")" "true"

    # A label list is one name per line, and the match must not depend on where
    # in the list the name appears.
    _expect "the label is found among others" \
        "$(skip_decision "$kind" "$(printf 'bug\n%s\nskip_aws_modules_eks_rds_os_tests\n' "skip_${kind}")")" "true"

    _expect "a checked box skips" \
        "$(skip_decision "$kind" "" "- [x] \`skip_${kind}\`")" "true"

    _expect "an upper-case checked box skips" \
        "$(skip_decision "$kind" "" "- [X] \`skip_${kind}\`")" "true"

    _expect "an unchecked box does not skip" \
        "$(skip_decision "$kind" "" "- [ ] \`skip_${kind}\`")" "false"

    _expect "a checked box for a longer label does not skip" \
        "$(skip_decision "$kind" "" "- [x] \`${longer}\`")" "false"

    _expect "a checked skip_all box skips" \
        "$(skip_decision "$kind" "" "- [x] \`skip_all\`")" "true"

    _expect "an unchecked skip_all box does not skip" \
        "$(skip_decision "$kind" "" "- [ ] \`skip_all\`")" "false"

    [[ "$failures" -eq 0 ]] || return 1
}

if [[ "${1:-}" == "selftest" ]]; then
    selftest
    exit $?
fi

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <workflow_file_name_without_extension> | selftest" >&2
    exit 1
fi

skip_decision "$1" "${SKIP_LABELS:-}" "${SKIP_CHECKLIST:-}"

#!/usr/bin/env python3
"""Assert that a workflow filters on every composite action it uses.

`on.pull_request.paths` decides whether a workflow runs at all. A workflow
that calls `./.github/actions/foo` but does not list `.github/actions/foo/**`
in its filter never runs when `foo` changes, so the suites that exercise the
action are not the ones gating the edit to it.

Nothing failed when this drifted. Eleven actions had accumulated in that
state, among them `kubernetes-ingress-cleanup` and `kubernetes-keycloak-operator`
— both of which only execute at provisioning or teardown, where a regression
leaks paid infrastructure instead of turning a test red. Edits to them were
covered only when the same pull request happened to touch a filtered path too.

This is the gap `check-path-filters.py` documents as out of its scope: that
one asks whether each pattern still matches something, this one asks whether
the pattern set is complete. Both are decidable from the tree; neither implies
the other.

Scope: local composite actions only (`uses: ./.github/actions/<name>`).
Remote `uses:` are versioned by ref, not by path, so no filter applies. A
workflow with no path filter at all is not reported: it already runs on every
pull request, so nothing can be missing from a filter it does not have.

Stdlib only, and only the `uses:` and filter shapes this repository writes.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

WORKFLOWS = Path(".github/workflows")
ACTIONS = Path(".github/actions")

# `            - uses: ./.github/actions/internal-clean-namespace` and the
# `              uses: ./.github/actions/...` step form.
USES = re.compile(r"^\s*(?:- )?uses:\s*['\"]?\./\.github/actions/(?P<name>[A-Za-z0-9._-]+)")
# `            - .github/actions/internal-clean-namespace/**`
FILTERED = re.compile(r"^\s*- ['\"]?!?\.github/actions/(?P<name>[A-Za-z0-9._-]+)/\*\*")
# A workflow gates on paths only under these events.
HAS_FILTER = re.compile(r"^\s*paths(?:-ignore)?:\s*$")

# An action a workflow uses but deliberately does not gate on.
ESCAPE = "lint: unfiltered-action"

# Shared CI plumbing: used by nearly every workflow, and carrying no deployment
# semantics of its own. Gating on these would make one edit to the skip
# machinery, the matrix builder or the AWS credential helper queue every cloud
# suite at once — the fan-out AGENTS.md ("CI cost and skip labels") exists to
# prevent, and which the skip labels then have to undo by hand.
#
# The dividing line is deployment semantics, not popularity: anything that
# provisions, configures, tests or tears down a Camunda deployment stays
# gated, however many workflows use it. Adding an entry here removes CI
# coverage, so it needs a reason that survives that reading.
SHARED_PLUMBING = frozenset(
    {
        "internal-triage-skip",  # the skip-label gate itself, in 33 workflows
        "internal-apply-skip-label",  # writes the labels the gate reads
        "internal-tests-matrix",  # assembles the job matrix
        "internal-terraform-golden-plan",  # golden-plan runner, gated by its own paths
        "internal-debug-failed-pods",  # diagnostics, runs only after a failure
        "internal-generic-encrypt-export",  # artifact transport between jobs
        "internal-generic-decrypt-import",  # artifact transport between jobs
        "aws-configure-cli",  # credential/profile setup
    }
)


def scan(path: Path) -> tuple[set[str], set[str], bool]:
    """Return (actions used, actions filtered, workflow has any path filter)."""
    used: set[str] = set()
    filtered: set[str] = set()
    has_filter = False
    for line in path.read_text().splitlines():
        if ESCAPE in line:
            m = USES.match(line)
            if m:
                filtered.add(m.group("name"))
            continue
        if HAS_FILTER.match(line):
            has_filter = True
        m = FILTERED.match(line)
        if m:
            filtered.add(m.group("name"))
            continue
        m = USES.match(line)
        if m:
            used.add(m.group("name"))
    return used, filtered, has_filter


def check_file(path: Path) -> list[str]:
    used, filtered, has_filter = scan(path)
    if not has_filter:
        return []
    candidates = used - filtered - SHARED_PLUMBING
    missing = sorted(n for n in candidates if (ACTIONS / n).is_dir())
    return [
        f"{path}: uses .github/actions/{name} but does not filter on "
        f".github/actions/{name}/**"
        for name in missing
    ]


def main() -> int:
    problems: list[str] = []
    for path in sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml")):
        problems.extend(check_file(path))
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(
            f"\n{len(problems)} action(s) used without a matching path filter. "
            f"Add the path, or mark the `uses:` line with `{ESCAPE}`.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

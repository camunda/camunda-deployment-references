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

A workflow reaches an action transitively too: a create action that calls
`internal-terraform-drift-detect` puts that action on the workflow's real
dependency set, and an edit to it must queue the same suites. The closure is
followed through each action's own `uses:`.

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
# `            - .github/actions/internal-clean-namespace/**`. A leading `!`
# excludes the path from the trigger, so it gates nothing and must not match.
FILTERED = re.compile(r"^\s*- ['\"]?\.github/actions/(?P<name>[A-Za-z0-9._-]+)/\*\*")
# `on:` / `    pull_request:` / `        paths:`
MAPPING_KEY = re.compile(r"^(?P<indent> *)(?P<name>[A-Za-z_][A-Za-z0-9_-]*):(?P<rest>.*)$")
# Only `paths` under one of these gates the workflow. `paths` under a step's
# `with:` is an action input, and `paths-ignore` is a blocklist: a workflow
# carrying only that one already triggers on paths it does not name.
FILTER_EVENTS = ("pull_request", "pull_request_target", "push")

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


def action_dependencies() -> dict[str, set[str]]:
    """Map each local action to the local actions its own `uses:` names."""
    graph: dict[str, set[str]] = {}
    for directory in sorted(p for p in ACTIONS.iterdir() if p.is_dir()):
        manifest = directory / "action.yml"
        if not manifest.is_file():
            graph[directory.name] = set()
            continue
        graph[directory.name] = {
            m.group("name")
            for line in manifest.read_text().splitlines()
            if (m := USES.match(line))
        }
    return graph


def reachable(roots: set[str], graph: dict[str, set[str]]) -> set[str]:
    """Every local action a workflow runs, directly or through another action."""
    seen: set[str] = set()
    stack = list(roots)
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        stack.extend(graph.get(name, ()))
    return seen


def scan(path: Path) -> tuple[set[str], dict[str, set[str]]]:
    """Return (actions used, {event: actions gated on under that event}).

    Coverage is tracked per event because each one queues the workflow on its
    own: an action listed under `pull_request.paths` but not `push.paths`
    still cannot trigger the suite on a push that only touches that action.

    `paths` is only a trigger filter directly under `on.<event>` for one of
    FILTER_EVENTS. The same key under a step's `with:` is an action input, and
    `paths-ignore` is a blocklist, so neither opens a filter block here.
    """
    used: set[str] = set()
    filtered: dict[str, set[str]] = {}

    on_indent: int | None = None
    event_indent: int | None = None
    event: str | None = None
    paths_indent: int | None = None

    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key = MAPPING_KEY.match(line)
        indent = len(line) - len(line.lstrip())

        if key:
            name, ind = key.group("name"), len(key.group("indent"))
            if name == "on" and ind == 0:
                on_indent, event_indent, event, paths_indent = 0, None, None, None
                continue
            if on_indent is not None and ind == 0 and name != "on":
                on_indent, event, paths_indent = None, None, None
            if on_indent is not None and event_indent is None and ind > on_indent:
                event_indent = ind
            if on_indent is not None and ind == event_indent:
                event = name if name in FILTER_EVENTS else None
                paths_indent = None
            elif event and event_indent is not None and ind > event_indent:
                paths_indent = ind if name == "paths" else None
                if name == "paths":
                    filtered.setdefault(event, set())

        if paths_indent is not None and event and indent > paths_indent:
            m = FILTERED.match(line)
            if m:
                filtered[event].add(m.group("name"))
                continue

        if ESCAPE in line:
            m = USES.match(line)
            if m:
                for names in filtered.values():
                    names.add(m.group("name"))
                used.discard(m.group("name"))
                continue
        m = USES.match(line)
        if m:
            used.add(m.group("name"))
    return used, filtered


def check_file(path: Path, graph: dict[str, set[str]] | None = None) -> list[str]:
    used, filtered = scan(path)
    if not filtered:
        return []
    if graph is None:
        graph = action_dependencies()
    used = reachable(used, graph)
    problems: list[str] = []
    for event in sorted(filtered):
        missing = sorted(
            n
            for n in used - filtered[event] - SHARED_PLUMBING
            if (ACTIONS / n).is_dir()
        )
        problems.extend(
            f"{path}: uses .github/actions/{name} but does not filter on "
            f".github/actions/{name}/** under on.{event}.paths"
            for name in missing
        )
    return problems


def main() -> int:
    problems: list[str] = []
    graph = action_dependencies()
    for path in sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml")):
        problems.extend(check_file(path, graph))
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

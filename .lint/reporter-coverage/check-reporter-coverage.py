#!/usr/bin/env python3
"""Assert the CI events reporter watches every integration suite.

`internal_global_ci_events_reporter.yml` observes other workflows through
`on.workflow_run.workflows`, which matches by **display name**. That list is
maintained by hand, so it drifts silently: add a suite and nothing observes it,
rename one and its entry keeps pointing at a workflow that no longer exists.

Drift here is invisible in the worst way. The reporter is what catches a run
that dispatched no jobs, and such a run emits no check runs at all -- no
failure, no pending, nothing on the pull request. That is how the kind suite
stopped running on stable/8.8 for a fortnight (#3336). A suite missing from this
list has no observer of last resort, so the same silence would go unnoticed
again.

The check runs one way only: every `Tests - Integration - *` workflow on this
branch must be watched. The reverse is deliberately not enforced, because the
reporter lives on the default branch yet observes runs from every branch, so it
legitimately watches suites that exist only on a stable branch and have no file
here.

Stdlib only, and only the shapes the repository actually uses are parsed, so an
unrecognised one fails loudly instead of being silently skipped.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

WORKFLOWS = Path(".github/workflows")
REPORTER = WORKFLOWS / "internal_global_ci_events_reporter.yml"

# Only suites are observed. The prefix is the repository's own naming
# convention for them, documented in docs/ci.md under "Workflow Naming".
OBSERVED_PREFIX = "Tests - Integration - "

# A top-level `name:` sits at column zero; a step's `- name:` never does.
TOP_LEVEL_NAME = re.compile(r"^name:[ \t]+(?P<value>\S.*?)[ \t]*$")

KEY = re.compile(r"^(?P<indent>[ \t]*)(?P<key>[A-Za-z_][\w-]*):")
LIST_ENTRY = re.compile(r"^(?P<indent>[ \t]*)-[ \t]+(?P<value>\S.*?)[ \t]*$")


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" \t"))


def workflow_name(path: Path) -> str | None:
    """The display name a workflow reports to GitHub, or None if it declares none."""
    for line in path.read_text().splitlines():
        match = TOP_LEVEL_NAME.match(line)
        if match:
            return match.group("value")
    return None


def watched_workflows(path: Path) -> list[str]:
    """The names listed under `on.workflow_run.workflows` in the reporter."""
    names: list[str] = []
    list_indent: int | None = None

    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        if list_indent is None:
            key = KEY.match(line)
            if key and key.group("key") == "workflows":
                list_indent = indent_of(line)
            continue

        entry = LIST_ENTRY.match(line)
        if entry and len(entry.group("indent")) > list_indent:
            names.append(entry.group("value"))
            continue

        # Anything that is not a deeper list entry ends the block.
        break

    if list_indent is None:
        raise SystemExit(
            f"{path}: no `workflows:` list found under `on.workflow_run`. "
            "The reporter's shape changed; update this check rather than "
            "leaving the suites unobserved."
        )
    return names


def observed_suites(directory: Path) -> dict[str, Path]:
    """Every workflow in `directory` whose display name marks it as a suite."""
    suites: dict[str, Path] = {}
    for path in sorted(directory.glob("*.yml")) + sorted(directory.glob("*.yaml")):
        name = workflow_name(path)
        if name and name.startswith(OBSERVED_PREFIX):
            suites[name] = path
    return suites


def main() -> int:
    if not REPORTER.is_file():
        print(f"{REPORTER}: not found; cannot check reporter coverage.")
        return 1

    watched = set(watched_workflows(REPORTER))
    suites = observed_suites(WORKFLOWS)
    missing = sorted(set(suites) - watched)

    if missing:
        print("Integration suites the CI events reporter does not watch:\n")
        for name in missing:
            print(f"  {suites[name].name}: {name!r}")
        print(
            f"\nAdd each name to `on.workflow_run.workflows` in {REPORTER.name}. "
            "Until then a run of that suite which dispatches no jobs reports "
            "nothing anywhere: no check runs, so nothing on the pull request "
            "either."
        )
        return 1

    extra = sorted(watched - set(suites))
    print(f"{len(suites)} integration suites, all watched by the reporter.")
    if extra:
        # Not a failure: the reporter runs from the default branch and observes
        # every branch, so these plausibly name suites that live only on a
        # stable branch. Printed so a genuine typo is still visible.
        print(f"{len(extra)} watched name(s) with no workflow here:")
        for name in extra:
            print(f"  {name!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

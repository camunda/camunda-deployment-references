#!/usr/bin/env python3
"""Assert that every workflow path filter still matches a tracked file.

`on.pull_request.paths` decides whether a workflow runs at all. When a
directory is renamed and the filter is not renamed with it, nothing fails:
the pattern simply stops matching, the workflow stops being queued, and the
suite it guards silently disappears from every pull request.

That happened on `stable/8.8`. The EC2 suite filtered on `generic/debian/**`
long after the procedures moved to `generic/compute/debian/`, so no
procedure-only pull request could trigger it. The gap stayed invisible until
a weekly scheduled run failed on an upstream URL that had 404'd for weeks —
a break a pull request would have caught the day it was introduced (#3220).

The same audit found the pattern repeated: an action directory misspelled
(`auroa-manage-cluster`), a tool file misspelled (`.tools-versions`), actions
renamed without their filters (`internal-helm-chart-tests`), and golden-file
exclusions left pointing above the directory the goldens moved into — the
inverse waste, since a golden-only diff now launches a full cloud suite.

Scope: this checks that each pattern matches something, not that the pattern
set is complete. A workflow that forgets to list an action it uses is a real
gap this cannot see; a pattern that matches the wrong thing is another. Only
absence of any match is decidable from the tree alone, and it is the failure
mode that has actually cost this repository test coverage.

Matching is deliberately more permissive than GitHub's: `**` is treated as
"any characters", and a pattern with no wildcard also passes when it names a
tracked directory. Erring toward permissive keeps the check from failing a
filter that does work; the point is to catch the ones that cannot possibly.

Stdlib only, and only the filter shapes this repository actually writes are
parsed.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

WORKFLOWS = Path(".github/workflows")

# `paths` under one of these events gates the workflow; `paths` under a step's
# `with:` is an action input and must not be mistaken for one.
FILTER_EVENTS = ("pull_request", "pull_request_target", "push")
FILTER_KEYS = ("paths", "paths-ignore")

# `    pull_request:` or `        paths:`
MAPPING_KEY = re.compile(r"^(?P<indent> *)(?P<name>[A-Za-z_][A-Za-z0-9_-]*):(?P<rest>.*)$")
# `            - '!aws/compute/ec2-single-region/terraform/cluster/test/golden/**'`
LIST_ITEM = re.compile(r"^(?P<indent> *)- (?P<value>.+)$")

# A filter that names a path the tree does not have yet, on purpose.
ESCAPE = "lint: future-path"


class Filter:
    """One pattern under an `on.<event>.paths` block."""

    def __init__(self, line: int, event: str, key: str, pattern: str, raw: str) -> None:
        self.line = line
        self.event = event
        self.key = key
        self.pattern = pattern
        self.raw = raw


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def strip_value(raw: str) -> str:
    """Unquote a scalar and drop its trailing comment.

    Filters that start with `!` must be quoted in YAML, so both quote styles
    appear in the workflows, and a `#` inside a quoted pattern is data.
    """
    value = raw.strip()
    if value[:1] in ("'", '"'):
        quote = value[0]
        end = value.find(quote, 1)
        if end != -1:
            return value[1:end]
        return value[1:]
    return value.split(" #", 1)[0].strip()


def read_filters(path: Path) -> list[Filter]:
    """Collect the path filters of a workflow with an indentation stack.

    A real YAML parse would need PyYAML, which the lint hooks do not have.
    Tracking `(indent, key)` is enough to tell `on.pull_request.paths` from
    the `paths` input of a step, which is the only ambiguity that matters.
    """
    filters: list[Filter] = []
    stack: list[tuple[int, str]] = []

    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        item = LIST_ITEM.match(line)
        if item:
            indent = indent_of(line)
            while stack and stack[-1][0] >= indent:
                stack.pop()
            if len(stack) >= 2 and stack[-1][1] in FILTER_KEYS and stack[-2][1] in FILTER_EVENTS:
                pattern = strip_value(item.group("value"))
                filters.append(Filter(number, stack[-2][1], stack[-1][1], pattern, line))
            continue

        key = MAPPING_KEY.match(line)
        if not key:
            continue
        indent = indent_of(line)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        stack.append((indent, key.group("name")))

        inline = key.group("rest").strip()
        if inline.startswith("[") and key.group("name") in FILTER_KEYS and len(stack) >= 2 and stack[-2][1] in FILTER_EVENTS:
            for part in inline.strip("[]").split(","):
                if part.strip():
                    filters.append(Filter(number, stack[-2][1], key.group("name"), strip_value(part), line))

    return filters


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Translate a GitHub filter pattern into an anchored regex.

    `*` stops at a separator, `**` crosses them, `?` is a single character.
    A `**/` segment spans zero or more directories, so `a/**/go.mod` has to
    match `a/go.mod` as well: keeping that slash mandatory would report a
    working filter as dead the day the file moves up one level.
    """
    out = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "*":
            if pattern[index : index + 3] == "**/":
                out.append("(?:.*/)?")
                index += 3
                continue
            if pattern[index : index + 2] == "**":
                out.append(".*")
                index += 2
                continue
            out.append("[^/]*")
        elif char == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(char))
        index += 1
    return re.compile("".join(out) + r"\Z")


def is_alive(pattern: str, files: list[str]) -> bool:
    """Does the pattern still designate anything that is tracked?"""
    target = pattern.lstrip("!")
    if not target:
        return True
    if "*" not in target and "?" not in target:
        prefix = target.rstrip("/") + "/"
        return any(name == target or name.startswith(prefix) for name in files)
    matcher = glob_to_regex(target)
    return any(matcher.match(name) for name in files)


def tracked_files() -> list[str]:
    """List what git tracks, not what the checkout happens to contain.

    Scratch directories and session worktrees are gitignored but present on
    disk, and a dead pattern must not look alive because something untracked
    sits where the renamed directory used to be.
    """
    listing = subprocess.run(
        ["git", "ls-files", "-z"],
        capture_output=True,
        check=True,
        text=True,
    )
    return [name for name in listing.stdout.split("\0") if name]


def check_file(path: Path, files: list[str]) -> list[str]:
    problems = []
    for entry in read_filters(path):
        if ESCAPE in entry.raw or is_alive(entry.pattern, files):
            continue
        problems.append(
            f"{path}:{entry.line}: on.{entry.event}.{entry.key}: "
            f"'{entry.pattern}' matches no tracked file. "
            f"Point it at the path that replaced it, or drop it; "
            f"if the path is coming later, mark the line '# {ESCAPE}'."
        )
    return problems


def main() -> int:
    files = tracked_files()
    problems = []
    for workflow in sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml")):
        problems.extend(check_file(workflow, files))

    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(f"\n{len(problems)} path filter(s) matching nothing.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Assert that a job forced to run cannot read a matrix its producer never wrote.

Several test workflows build a job matrix from another job's output:

    strategy:
        matrix:
            distro: ${{ fromJson(needs.clusters-info.outputs.platform-matrix).distro }}

When the producing job is skipped -- which is what triage does to every workflow
a pull request carries a `skip_<workflow>` label for -- that output is the empty
string. A consumer gated only by `always()` is still scheduled, `fromJson('')`
cannot be evaluated, and GitHub gives up before the job exists: the job is
absent from the run and the run concludes `failure` while every job in it reads
`success` or `skipped`.

The damage is not the missing cleanup, which had nothing to clean. It is a red
run that no change to the pull request can turn green, on every skipped
workflow, which is how a genuinely broken suite stops being noticed. Before this
guard, 34 of the last 60 runs of the EKS dual-region suite ended that way.

`always()` is still wanted on those jobs: cleanup has to run when the tests
*failed*. The distinction that matters is failed versus skipped, so the fix is
to name the producer in the condition:

    if: always() && needs.clusters-info.result != 'skipped'

#3127 fixed this shape once, for the step that reads matrix *artifacts*, and
concluded the job matrices were safe because they carried no `if:`. Eight of
them did. Hence a check rather than another round of grep.

Stdlib only, in keeping with the other checks in `.lint/`. Only the constructs
the repository actually uses are parsed; an unrecognised shape fails loudly
rather than passing silently.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

WORKFLOWS = Path(".github/workflows")

# `jobs:` and, under it, `    cleanup-clusters:`
JOBS_KEY = re.compile(r"^(?P<indent>\s*)jobs:\s*(?:#.*)?$")
KEY = re.compile(r"^(?P<indent>\s*)(?P<name>[A-Za-z_][\w-]*):")

# `${{ fromJson(needs.clusters-info.outputs.platform-matrix).distro }}`
PRODUCER = re.compile(r"fromJson\(\s*needs\.(?P<job>[A-Za-z_][\w-]*)\.outputs\.")

# `        if: always() && ...`, including a folded continuation
IF_KEY = re.compile(r"^(?P<indent>\s*)if:\s*(?P<value>.*)$")


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def job_blocks(lines: list[str]) -> list[tuple[str, list[str]]]:
    """Return `(job name, body lines)` for every job in a workflow."""
    start = None
    jobs_indent = 0
    for i, line in enumerate(lines):
        match = JOBS_KEY.match(line)
        if match:
            start = i + 1
            jobs_indent = len(match.group("indent"))
            break
    if start is None:
        return []

    blocks: list[tuple[str, list[str]]] = []
    current: str | None = None
    body: list[str] = []
    job_indent: int | None = None

    for line in lines[start:]:
        if not line.strip() or line.lstrip().startswith("#"):
            if current:
                body.append(line)
            continue
        match = KEY.match(line)
        depth = indent_of(line)
        if match and depth <= jobs_indent:
            break  # left the `jobs:` mapping
        if match and (job_indent is None or depth == job_indent):
            if current:
                blocks.append((current, body))
            job_indent = depth
            current = match.group("name")
            body = []
            continue
        if current:
            body.append(line)

    if current:
        blocks.append((current, body))
    return blocks


def job_condition(body: list[str]) -> str | None:
    """Return the job-level `if:`, or None. Steps' `if:` are indented deeper.

    The value may span several lines: yamlfmt folds conditions past the line
    length limit, and some are written as block scalars. Both continue on lines
    indented deeper than the `if:` key itself, so both are joined back together
    before the caller looks for a guard in them.
    """
    top = min((indent_of(l) for l in body if l.strip()), default=0)
    for i, line in enumerate(body):
        match = IF_KEY.match(line)
        if not match or len(match.group("indent")) != top:
            continue
        value = match.group("value").strip()
        parts = [] if value in (">", ">-", "|", "|-") else [value]
        for nxt in body[i + 1 :]:
            if not nxt.strip():
                break
            if indent_of(nxt) <= top:
                break
            parts.append(nxt.strip())
        return " ".join(parts)
    return None


def offenders() -> list[str]:
    found: list[str] = []
    for path in sorted(WORKFLOWS.glob("*.yml")):
        lines = path.read_text().splitlines(keepends=True)
        for name, body in job_blocks(lines):
            producers = {m.group("job") for line in body for m in PRODUCER.finditer(line)}
            if not producers:
                continue
            condition = job_condition(body)
            if condition is None:
                continue  # no `if:`, so a skipped producer already skips this job
            if "always()" not in condition:
                continue  # not forced to run past a skipped producer
            unguarded = sorted(p for p in producers if f"needs.{p}.result" not in condition)
            if unguarded:
                found.append(
                    f"{path}: job '{name}' builds its matrix from "
                    f"{', '.join(unguarded)} but runs on always() without checking "
                    f"{' / '.join(f'needs.{p}.result' for p in unguarded)}"
                )
    return found


def main() -> int:
    if not WORKFLOWS.is_dir():
        print(f"{WORKFLOWS} not found; run from the repository root", file=sys.stderr)
        return 2
    found = offenders()
    for line in found:
        print(line, file=sys.stderr)
    if found:
        print(
            "\nAdd the producer to the condition, for example:\n"
            "    if: always() && needs.clusters-info.result != 'skipped'\n"
            "Without it the run concludes 'failure' whenever triage skips the suite.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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
workflow, which is how a genuinely broken suite stops being noticed. When this
was written (2026-08-27), 34 of the 60 most recent runs of the EKS dual-region
suite had ended that way -- a snapshot of what motivated the check, not a figure
anyone should expect to still reproduce.

`always()` is still wanted on those jobs: cleanup has to run when the tests
*failed*. The distinction that matters is failed versus skipped, so the fix is
to compare the producer's result in the condition:

    if: always() && needs.clusters-info.result != 'skipped'

A comparison, not a bare mention. `needs.<job>.result` on its own is a non-empty
string for every outcome, `skipped` among them, so `always() &&
needs.clusters-info.result` reads like a guard and is true in exactly the case
it is supposed to exclude.

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

# `needs.clusters-info.result != 'skipped'`, and every other comparison shape.
#
# Parsed rather than pattern-matched for "looks like a guard", because most
# comparisons are not one. `needs.<job>.result` alone is a non-empty string for
# every outcome, so `always() && needs.clusters-info.result` is true exactly
# when the guard is needed; and `!= 'failure'` is equally true for a skipped
# producer. See guards_against_skip for the only property that matters.
GUARD = re.compile(
    r"needs\.(?P<job>[A-Za-z_][\w-]*)\.result\s*(?P<op>[!=]=)\s*['\"](?P<value>[^'\"]*)['\"]"
)

# `        if: always() && ...`, including a folded continuation
IF_KEY = re.compile(r"^(?P<indent>\s*)if:\s*(?P<value>.*)$")


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def guards_against_skip(op: str, value: str) -> bool:
    """True when `needs.<job>.result <op> '<value>'` is FALSE for a skipped producer.

    That is the whole requirement, and it is not the same as "compares the
    result". Only two shapes satisfy it:

        != 'skipped'          false when skipped
        == '<anything else>'  false when skipped

    while `!= 'failure'` and `== 'skipped'` read like guards and leave the job
    scheduled on the exact run they were meant to protect.
    """
    return (op == "!=") == (value == "skipped")


def strip_comment(text: str) -> str:
    """Drop a YAML inline comment from a scalar.

    The guard check is a substring search, so a trailing
    `# needs.clusters-info.result is deliberately ignored` would satisfy it
    without the condition doing anything. A comment starts at a `#` that opens
    the line or follows whitespace, and only outside a quoted scalar — `'#'`
    inside quotes is data.
    """
    quote = ""
    for i, char in enumerate(text):
        if quote:
            if char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == "#" and (i == 0 or text[i - 1] in " \t"):
            return text[:i]
    return text


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
    before the caller looks for a guard in them. Comments are dropped on the
    way, so prose about the condition is never mistaken for the condition.
    """
    top = min((indent_of(l) for l in body if l.strip()), default=0)
    for i, line in enumerate(body):
        match = IF_KEY.match(line)
        if not match or len(match.group("indent")) != top:
            continue
        value = strip_comment(match.group("value")).strip()
        parts = [] if value in (">", ">-", "|", "|-") else [value]
        for nxt in body[i + 1 :]:
            if not nxt.strip():
                break
            if indent_of(nxt) <= top:
                break
            parts.append(strip_comment(nxt).strip())
        return " ".join(p for p in parts if p)
    return None


def offenders() -> list[str]:
    found: list[str] = []
    for path in sorted(WORKFLOWS.glob("*.yml")):
        lines = path.read_text().splitlines(keepends=True)
        for name, body in job_blocks(lines):
            # Comments stripped here for the same reason as in job_condition,
            # but the failure runs the other way: a commented-out matrix line
            # would invent a producer and fail a job that has none. A lint that
            # cries wolf gets deleted.
            producers = {
                m.group("job")
                for line in body
                for m in PRODUCER.finditer(strip_comment(line))
            }
            if not producers:
                continue
            condition = job_condition(body)
            if condition is None:
                continue  # no `if:`, so a skipped producer already skips this job
            if "always()" not in condition:
                continue  # not forced to run past a skipped producer
            guarded = {
                m.group("job")
                for m in GUARD.finditer(condition)
                if guards_against_skip(m.group("op"), m.group("value"))
            }
            unguarded = sorted(producers - guarded)
            if unguarded:
                found.append(
                    f"{path}: job '{name}' builds its matrix from "
                    f"{', '.join(unguarded)} but runs on always() without comparing "
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

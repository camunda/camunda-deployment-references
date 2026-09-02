#!/usr/bin/env python3
"""Assert that every scenario a test workflow creates state for can be reclaimed.

Some test workflows embed the scenario name in the S3 prefix their terraform
state is written to:

    S3_BACKEND_BUCKET_PREFIX=azure/kubernetes/${{ matrix.scenario.name }}/

Adding a scenario to such a workflow silently adds a new state tree. If the
daily cleanup does not enumerate the same scenarios, that tree is never listed:
the cleanup finds nothing, exits 0, and stays green while the clusters keep
running and keep consuming quota. That is exactly what happened when
`aks-single-region-rdbms` was added in #2157 while the cleanup still hardcoded
`azure/kubernetes/aks-single-region/`, and it went unnoticed for months.

Scope: only scenario-templated prefixes are checked. A workflow with a fixed
prefix cannot acquire an unreclaimed state tree by gaining a scenario, and the
cleanups covering those use varying mechanisms (some scan the whole bucket and
filter on the Camunda version rather than on a key prefix), which this check
deliberately does not try to model. That scope restriction applies to what is
checked, not to what reclaims: a cleanup pinned to a literal prefix still
reclaims that tree and is counted as coverage.

Stdlib only, and only the constructs the repository actually uses are parsed, so
an unrecognised shape fails loudly instead of being silently skipped.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

WORKFLOWS = Path(".github/workflows")

SCENARIO_PLACEHOLDER = re.compile(r"\$\{\{\s*matrix\.scenario\.name\s*\}\}")

# `S3_BACKEND_BUCKET_PREFIX: aws/compute/ec2-single-region/ # comment`
ENV_PREFIX = re.compile(r"^\s*S3_BACKEND_BUCKET_PREFIX:\s*(?P<value>\S+)")

# `echo "S3_BACKEND_BUCKET_PREFIX=azure/kubernetes/${{ ... }}/" | tee -a ...`
ECHO_PREFIX = re.compile(r"S3_BACKEND_BUCKET_PREFIX=(?P<value>[^\"']+)")

CI_MATRIX_FILE = re.compile(r"^\s*CI_MATRIX_FILE:\s*(?P<value>\S+)")

# `- name: aks-single-region`
LIST_NAME = re.compile(r"^(?P<indent>\s*)-\s+name:\s*(?P<value>\S+)")

KEY = re.compile(r"^(?P<indent>\s*)(?P<key>[A-Za-z_][\w-]*):")


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def scenario_names(path: Path) -> list[str]:
    """Collect the `- name:` entries of every `scenario:` block in a file.

    A `test_matrix.yml` and a cleanup workflow's inline strategy matrix share
    this shape, so one reader serves both. A workflow can hold several such
    blocks, one per job, and each of them feeds its scenario into a state
    prefix, so reading only the first would under-report a multi-job workflow.
    """
    names: list[str] = []
    block_indent: int | None = None

    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        key = KEY.match(line)

        if block_indent is None:
            if key and key.group("key") == "scenario":
                block_indent = indent_of(line)
            continue

        # Any key at or above the `scenario:` level ends the current block. Keep
        # reading: that key may itself be a later job's own `scenario:`.
        if key and indent_of(line) <= block_indent:
            starts_another_block = key.group("key") == "scenario"
            block_indent = indent_of(line) if starts_another_block else None
            continue

        entry = LIST_NAME.match(line)
        if entry and len(entry.group("indent")) > block_indent:
            name = entry.group("value")
            if name not in names:
                names.append(name)

    return names


def read_workflow(path: Path) -> tuple[set[str], list[str]]:
    """Return the state prefixes a workflow declares and the scenarios it knows."""
    prefixes: set[str] = set()
    matrix_file: Path | None = None

    for line in path.read_text().splitlines():
        env = ENV_PREFIX.match(line)
        if env:
            prefixes.add(env.group("value"))
            continue

        echoed = ECHO_PREFIX.search(line)
        if echoed:
            prefixes.add(echoed.group("value"))
            continue

        matrix = CI_MATRIX_FILE.match(line)
        if matrix:
            candidate = Path(matrix.group("value"))
            if candidate.is_file():
                matrix_file = candidate

    scenarios = scenario_names(matrix_file) if matrix_file else []
    if not scenarios:
        # A cleanup workflow may enumerate its scenarios inline instead.
        scenarios = scenario_names(path)

    return prefixes, scenarios


def templated_prefixes(path: Path) -> set[str]:
    """Expand the scenario-templated prefixes of a workflow.

    Fixed prefixes are dropped: they are out of scope as something to check.
    Use `reclaimed_prefixes` for the cleanup side, where they do count. A
    templated prefix with no resolvable scenario list is an error, not an empty
    result, otherwise the very drift this guards against would read as a pass.
    """
    prefixes, scenarios = read_workflow(path)
    templated = {p for p in prefixes if SCENARIO_PLACEHOLDER.search(p)}
    if not templated:
        return set()

    if not scenarios:
        raise SystemExit(
            f"{path}: uses a scenario-templated state prefix but declares no "
            f"scenario list (neither CI_MATRIX_FILE nor an inline matrix)"
        )

    return {
        SCENARIO_PLACEHOLDER.sub(scenario, prefix)
        for prefix in templated
        for scenario in scenarios
    }


def reclaimed_prefixes(path: Path) -> set[str]:
    """Return every state prefix a daily cleanup reclaims.

    Fixed prefixes are out of scope on the test side only: there, they cannot
    acquire an unreclaimed tree by gaining a scenario. A cleanup pinned to a
    literal prefix does reclaim that one tree, which is how a single-scenario
    test workflow is covered on branches predating #2978.
    """
    prefixes, _ = read_workflow(path)
    fixed = {p for p in prefixes if not SCENARIO_PLACEHOLDER.search(p)}
    return fixed | templated_prefixes(path)


def main() -> int:
    if not WORKFLOWS.is_dir():
        raise SystemExit(f"{WORKFLOWS} not found; run from the repository root")

    cleanups = sorted(WORKFLOWS.glob("*daily_cleanup*.yml"))
    # Everything else is a candidate writer. Keying this off a `_tests` /
    # `_test` filename suffix would reopen the very hole being guarded: a
    # workflow that writes scenario-templated state under an off-convention
    # name would be skipped in silence. Only workflows that declare such a
    # prefix survive the filter below, so widening the scan costs nothing.
    reclaimers = set(cleanups)
    tests = [p for p in sorted(WORKFLOWS.glob("*.yml")) if p not in reclaimers]

    written = {p: templated_prefixes(p) for p in tests}
    written = {p: v for p, v in written.items() if v}

    covered: set[str] = set()
    for path in cleanups:
        covered |= reclaimed_prefixes(path)

    failures = [
        f"{path}: no daily cleanup reclaims {sorted(prefixes - covered)}"
        for path, prefixes in written.items()
        if prefixes - covered
    ]

    if failures:
        print("Terraform state written by tests that no daily cleanup reclaims:\n")
        for failure in failures:
            print(f"  {failure}")
        print(
            "\nAdd the scenario to the matching daily cleanup workflow, or derive "
            "its matrix from the same test_matrix.yml the tests use, as "
            "azure_aks_single_region_daily_cleanup.yml does."
        )
        return 1

    total = sum(len(v) for v in written.values())
    print(f"{total} scenario-templated state prefixes, all reclaimed by a cleanup.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

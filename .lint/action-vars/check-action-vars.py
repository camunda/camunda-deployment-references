#!/usr/bin/env python3
"""Assert that a variable written in a workflow resolves where it is written.

GitHub interpolates `${{ ... }}` and nothing else. A shell-style `${VAR}` is
only meaningful inside a `run:` body, where the shell expands it from the step's
`env:`. Written into a `with:` or `env:` *value* it is stored verbatim, and the
step runs on a literal eleven-word string instead of a version, a token or a
bucket name — silently, because nothing in the toolchain reads those values.

That is not hypothetical. Rewriting `${{ inputs.openshift-version }}` into
`${INPUTS_OPENSHIFT_VERSION}` under a `with:` sent the OpenShift installer
looking for a release by that name and crashed the nightly cleanup before it
destroyed a single cluster:

    Installing oc matching version "${INPUTS_OPENSHIFT_VERSION}"
    .../openshift-tools-installer/dist/index.js:22

The same rewrite moves values out of the script and into `env:`, which is where
the second failure mode comes from: an `env:` block that lands on the wrong step
leaves the reader with the variable unset and the declaration dead. Under
`set -u` the reader aborts; without it, it quietly uses an empty string.

Three rules, all cheap to state:

1. no shell-style `${UPPER_CASE}` in an `env:` or `with:` value;
2. every `INPUTS_*` a step reads is declared in scope;
3. every `INPUTS_*` a step declares is read by that step.

Lower-case `${name}` is left alone: it is the templating syntax of the actions
this repository calls (korthout/backport-action and friends), never the output
of an expression rewrite, which is upper-case by convention.

Escape hatches, both per line:

    FOO: ${HOME}/bin           # lint: literal-var   -- rule 1
    INPUTS_BAR: ${{ inputs.bar }}  # lint: external-var  -- rule 3

Stdlib only, and only the shapes this repository actually writes are parsed:
block scalars, and mappings indented under `env:`, `with:` and `steps:`. An
unrecognised shape is skipped rather than guessed at, so this check never
invents a finding — it is a floor, not a full YAML reader.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TARGETS = (Path(".github/workflows"), Path(".github/actions"))

# `oc: ${INPUTS_OPENSHIFT_VERSION}` but not `oc: ${{ inputs.openshift-version }}`
SHELL_VAR = re.compile(r"\$\{(?!\{)(?P<name>[A-Z_][A-Z0-9_]*)\}")
# `"$INPUTS_TAGS"` — the unbraced form, only when it is the whole value.
BARE_VAR = re.compile(r"^\"?\$(?P<name>[A-Z_][A-Z0-9_]*)\"?$")
# Any reference, braced or not, as a script reads it.
ANY_REF = re.compile(r"\$\{?(?P<name>INPUTS_[A-Z0-9_]+)\}?")

MAPPING_KEY = re.compile(r"^(?P<indent> *)(?P<key>[A-Za-z_][\w.-]*):(?P<rest>.*)$")
LIST_ITEM = re.compile(r"^(?P<indent> *)- (?P<rest>\S.*)$")

# Inputs whose value is a script, so a shell-style reference is legitimate.
SCRIPT_KEYS = frozenset({"run", "command", "script"})

LITERAL_ESCAPE = "lint: literal-var"
EXTERNAL_ESCAPE = "lint: external-var"


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def is_structural(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and not stripped.startswith("#")


def block_body(lines: list[str], start: int, outer_indent: int) -> tuple[list[str], int]:
    """Return the lines indented deeper than `outer_indent`, and where they end."""
    end = start
    while end < len(lines):
        line = lines[end]
        if is_structural(line) and indent_of(line) <= outer_indent:
            break
        end += 1
    return lines[start:end], end


class Entry:
    """One `key: value` under an `env:` or `with:` block."""

    def __init__(self, key: str, value: str, line: int, raw: str) -> None:
        self.key = key
        self.value = value
        self.line = line
        self.raw = raw


class Step:
    def __init__(self, name: str, line: int, indent: int) -> None:
        self.name = name
        self.line = line
        self.indent = indent
        self.env: list[Entry] = []
        self.with_: list[Entry] = []
        self.scripts: list[str] = []


def read_mapping(lines: list[str], start: int, outer_indent: int, offset: int) -> list[Entry]:
    """Read `key: value` pairs directly under a block, block scalars included.

    `offset` is the absolute index of `lines[0]`, so findings can name the line
    the reader will open, not the step it belongs to.
    """
    body, _ = block_body(lines, start, outer_indent)
    entries: list[Entry] = []
    inner_indent = None
    index = 0
    while index < len(body):
        line = body[index]
        here = start + index
        index += 1
        if not is_structural(line):
            continue
        match = MAPPING_KEY.match(line)
        if match is None:
            continue
        if inner_indent is None:
            inner_indent = len(match.group("indent"))
        if len(match.group("indent")) != inner_indent:
            continue  # nested structure; not a value this check understands
        rest = match.group("rest").strip()
        if rest.startswith("|") or rest.startswith(">"):
            scalar, index = block_body(body, index, inner_indent)
            rest = "\n".join(scalar)
        entries.append(Entry(match.group("key"), rest, offset + here + 1, line))
    return entries


def read_steps(lines: list[str]) -> list[Step]:
    steps: list[Step] = []
    for number, line in enumerate(lines):
        match = MAPPING_KEY.match(line)
        if match is None or match.group("key") != "steps" or match.group("rest").strip():
            continue
        body, _ = block_body(lines, number + 1, len(match.group("indent")))
        steps.extend(read_step_block(body, number + 1))
    return steps


def read_step_block(body: list[str], offset: int) -> list[Step]:
    items = [index for index, line in enumerate(body) if LIST_ITEM.match(line)]
    if not items:
        return []
    item_indent = min(indent_of(body[index]) for index in items)
    boundaries = [index for index in items if indent_of(body[index]) == item_indent]
    steps: list[Step] = []
    for position, start in enumerate(boundaries):
        end = boundaries[position + 1] if position + 1 < len(boundaries) else len(body)
        steps.append(read_step(body[start:end], offset + start))
    return steps


def read_step(body: list[str], offset: int) -> Step:
    item = LIST_ITEM.match(body[0])
    key_indent = len(item.group("indent")) + 2
    flattened = [" " * key_indent + item.group("rest")] + body[1:]
    name = "?"
    step = Step(name, offset + 1, key_indent)
    index = 0
    while index < len(flattened):
        line = flattened[index]
        index += 1
        match = MAPPING_KEY.match(line)
        if match is None or len(match.group("indent")) != key_indent:
            continue
        key = match.group("key")
        rest = match.group("rest").strip()
        if key == "name":
            step.name = rest.strip("'\"")
        elif key in ("env", "with") and not rest:
            entries = read_mapping(flattened, index, key_indent, offset)
            if key == "env":
                step.env = entries
            else:
                step.with_ = entries
                step.scripts.extend(
                    entry.value for entry in entries if entry.key in SCRIPT_KEYS
                )
        elif key == "run":
            if rest.startswith("|") or rest.startswith(">"):
                scalar, index = block_body(flattened, index, key_indent)
                step.scripts.append("\n".join(scalar))
            else:
                step.scripts.append(rest)
    return step


def outer_env_names(lines: list[str], step: Step) -> set[str]:
    """Names from `env:` blocks shallower than the step: workflow and job level.

    A block counts only while the mapping that holds it is still open at the
    step, so one job's `env:` never lends its names to the next job's steps.
    """
    names: set[str] = set()
    step_index = step.line - 1
    for number, line in enumerate(lines):
        match = MAPPING_KEY.match(line)
        if match is None or match.group("key") != "env" or match.group("rest").strip():
            continue
        block_indent = len(match.group("indent"))
        if block_indent >= step.indent or number > step_index:
            continue
        if not still_open(lines, number, step_index, block_indent):
            continue
        names.update(
            entry.key for entry in read_mapping(lines, number + 1, block_indent, 0)
        )
    return names


def still_open(lines: list[str], start: int, target: int, indent: int) -> bool:
    """True while the mapping holding `lines[start]` has not been closed by `target`.

    A sibling key one level out — the next job under `jobs:` — ends it.
    """
    return not any(
        is_structural(line) and indent_of(line) < indent
        for line in lines[start + 1 : target + 1]
    )


def check_file(path: Path) -> list[str]:
    lines = path.read_text().splitlines()
    problems: list[str] = []
    for step in read_steps(lines):
        declared = {entry.key for entry in step.env} | outer_env_names(lines, step)
        script = "\n".join(step.scripts)

        for entry in step.env + step.with_:
            if entry.key in SCRIPT_KEYS or LITERAL_ESCAPE in entry.raw:
                continue
            hit = SHELL_VAR.search(entry.value) or BARE_VAR.match(entry.value.strip())
            if hit is None:
                continue
            problems.append(
                f"{path}:{entry.line}: step '{step.name}': '{entry.key}' is set to "
                f"the literal string '${{{hit.group('name')}}}'. GitHub only "
                f"expands ${{{{ ... }}}} here; use the expression, or add "
                f"'# {LITERAL_ESCAPE}' if the literal is intended."
            )

        for name in sorted(set(ANY_REF.findall(script))):
            if name not in declared:
                problems.append(
                    f"{path}:{step.line}: step '{step.name}': reads ${{{name}}} but "
                    f"no env in scope declares it. An env block that belongs to "
                    f"this step is probably attached to another one."
                )

        for entry in step.env:
            if not entry.key.startswith("INPUTS_") or EXTERNAL_ESCAPE in entry.raw:
                continue
            if re.search(rf"\$\{{?{re.escape(entry.key)}\b}}?", script):
                continue
            problems.append(
                f"{path}:{entry.line}: step '{step.name}': declares {entry.key} but "
                f"never reads it. Move it to the step that does, or add "
                f"'# {EXTERNAL_ESCAPE}' if a script it calls consumes it."
            )
    return problems


def main() -> int:
    problems: list[str] = []
    for target in TARGETS:
        for path in sorted(target.rglob("*.yml")) + sorted(target.rglob("*.yaml")):
            problems.extend(check_file(path))
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"\n{len(problems)} unresolvable variable reference(s).",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

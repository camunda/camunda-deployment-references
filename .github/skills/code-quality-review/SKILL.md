---
name: code-quality-review
description: 'Run a deliberately strict maintainability review of a diff: oversized files, spaghetti-condition growth, dead flexibility, and duplication inside a single module. USE WHEN: the user invokes "/code-quality-review", says "strict quality review", "deep code quality audit", "harsh maintainability review", or the review-loop skill reaches its self-review step. INVOKES: git diff, ripgrep, wc. DO NOT USE FOR: correctness or security review (Copilot and the normal review pass own those), or for DRY-ing code across cloud providers — that duplication is intentional here.'
argument-hint: '[base-ref] (defaults to the merge base with the target branch)'
---

# Code Quality Review

A deliberately harsh maintainability pass over a diff, run **before** asking for
a machine review. It looks at implementation quality, abstraction quality, and
codebase health — not at whether the code is correct.

Adapted from the `thermo-nuclear-code-quality-review` skill in
[cursor/plugins](https://github.com/cursor/plugins/tree/main/cursor-team-kit),
MIT License, Copyright (c) 2026 Cursor. The full license text is reproduced in
[NOTICE](./NOTICE), as MIT requires. The strict checks are kept; the upstream
"restructure the codebase" ambition is deliberately removed — see
[Non-goals](#non-goals).

## When to use

- Step 1.5 of the [review-loop](../review-loop/SKILL.md), before the Copilot
  review is requested.
- On demand, when a diff feels bloated and you want a second opinion before
  pushing.

## Non-goals

This repository ships **reference architectures: demos and learning
blueprints**, not a product codebase. That changes what "good" means, and this
skill must not fight it.

- **Do not** factor shared code across `aws/`, `azure/`, `generic/`, or across
  deployment options. Each deployment is meant to be readable and copyable on
  its own. Duplication between providers is a feature, not debt.
- **Do not** introduce an abstraction whose only justification is elegance. A
  reader copying one directory must still understand it standalone.
- **Do not** propose a restructuring that spans modules the diff never touched.
  Scope stays inside the diff and its immediate neighbours.
- **Do not** rewrite golden files to make a check pass — regenerate them through
  the documented `just` recipe.
- Correctness, security, and CI failures are out of scope. Copilot covers the
  first two in the review-loop; `ci-feedback-loop` covers the third.

## Checks

Report a finding only when it is actionable. An empty report is a valid result.

### 1. File growth

Do not let a diff push a file from under 1000 lines to over 1000 lines without a
strong reason.

```bash
# Prefer the remote-tracking ref, fall back to a local branch of the same name,
# so this also works on a fork or a clone that has not fetched the target yet.
TARGET=$(cat .target-branch)
BASE=${1:-$(git merge-base HEAD "origin/$TARGET" 2>/dev/null \
         || git merge-base HEAD "$TARGET")}
git diff --name-only "$BASE"...HEAD | while read -r f; do
  [ -f "$f" ] || continue
  now=$(wc -l < "$f")
  was=$(git show "$BASE:$f" 2>/dev/null | wc -l)
  [ "$now" -gt 1000 ] && [ "$was" -le 1000 ] \
    && printf '%s: %s -> %s lines (crossed 1000)\n' "$f" "$was" "$now"
done
```

Prefer extracting a submodule, a local, or a helper script over letting a file
sprawl. Waive it only when the file is still clearly organised and splitting it
would separate things that are read together.

### 2. Spaghetti-condition growth

Flag a conditional that gains yet another branch, flag, or special case instead
of being restated. This is the most common way these workflows and Terraform
locals rot.

- A `count`/`for_each` expression with stacked ternaries.
- A workflow `if:` accumulating `&&`/`||` clauses nobody can evaluate by eye.
- A shell `case` growing a branch per cloud provider inside a shared script.

### 3. Dead flexibility

- A Terraform variable no module reads.
- A workflow input with exactly one caller passing exactly one value.
- A module parameter that exists "for later".

Delete it. It can come back when a second caller does.

### 4. Duplication inside one module

Repeated blocks **within** a single module or workflow are real debt, unlike
cross-provider duplication. Look for copy-pasted resource blocks that differ by
one attribute, and repeated shell fragments that belong in a `just` recipe.

### 5. IaC-specific smells

- A hardcoded value (region, instance type, version, CIDR) that every other
  comparable resource takes from a variable.
- A `variable` block with no `description` — `terraform-docs` renders it into
  the module README, so an empty description ships to readers.
- A resource created inline that bypasses the established module pattern for
  that concern.
- Shell logic inlined in a workflow step that duplicates an existing `just`
  recipe, so CI and local runs can drift.

## Output

One line per finding:

```
<file>:L<line>: <check>: <problem>. <fix>.
```

Group by check. End with the verdict:

- `clean` — nothing actionable.
- `<n> finding(s)` — list them, worst first.

Report findings. Do **not** apply them unless the caller asked for fixes.

## Anti-patterns

- **Don't** widen scope to modules the diff never touched.
- **Don't** flag cross-provider duplication — see [Non-goals](#non-goals).
- **Don't** report style nits already enforced by pre-commit (`terraform fmt`,
  `yamlfmt`, `shellcheck`, `actionlint`). The hooks own those.
- **Don't** invent a refactor with no caller asking for it.
- **Don't** treat an empty report as a failure to try harder.

## References

- [review-loop](../review-loop/SKILL.md) — the PR loop that calls this at step 1.5.
- [ci-feedback-loop](../ci-feedback-loop/SKILL.md) — CI status/logs/artifacts.
- `AGENTS.md` → "Critical Rules" — reference architectures are blueprints, not products.
- Upstream: [thermo-nuclear-code-quality-review](https://github.com/cursor/plugins/blob/main/cursor-team-kit/skills/thermo-nuclear-code-quality-review/SKILL.md) (MIT).

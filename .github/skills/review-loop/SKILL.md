---
name: review-loop
description: 'Drive one or more pull requests to a review-ready state by pausing CI, self-reviewing the diff for maintainability, requesting a GitHub Copilot review, fixing every finding, re-requesting until the review is clean, then re-running the tests and appending the exact ` [ready]` tag (leading space) to the end of the PR title. USE WHEN: the user invokes "/review-loop", or says "pause the CI and get a Copilot review", "run the review loop", "fix what Copilot says and re-review", "drive this PR to ready", "mets le PR en ready". INVOKES: the ci-feedback-loop CLI (`review` subcommands + test triage), the code-quality-review skill for the pre-review self-check. DO NOT USE FOR: merging PRs, or one-off log fetching (use ci-feedback-loop directly).'
argument-hint: '[pr-number|pr-url ...] (defaults to the current branch PR + its backport PRs)'
---

# PR Review Loop

Autonomously drive a PR (and its sibling backport PRs) through this loop:

```
pause CI → self-review the diff → request Copilot review → fix every finding
        → re-review (loop until clean)
        → relaunch tests → on failure: fix + re-enter loop → on success: append " [ready]"
```

The goal is a PR that is green and has no outstanding Copilot findings, marked
ready for human review — **without ever merging it**.

## When to use

- The user wants a hands-off "get this PR reviewed and green" cycle.
- A change spans a main PR + one or more `backport-*-to-stable/*` PRs that must stay in sync.

## Prerequisites

- `gh` authenticated (`gh auth status`) with permissions for everything the
  loop touches: **pull-requests: write** (request reviews, edit the title),
  **issues: write** (add/remove the `skip_all` label), and **actions: write**
  (cancel/rerun workflow runs). A classic token with the `repo` + `workflow`
  scopes covers all three.
- `go` ≥ 1.23 on `PATH`, for the CLI below.
- Working dir inside the target repo; the feature branch is pushed.

## The CLI

The choreography — resolving the PR set, the `skip_all` lifecycle, reading
Copilot's findings, tagging — lives in the **ci-feedback-loop** CLI rather than
in this file, so its idempotency is tested rather than asserted. Define the
alias once per shell:

```bash
ci_fb() { (cd "$(git rev-parse --show-toplevel)/.github/skills/ci-feedback-loop" && go run . "$@"); }
```

Every `ci_fb review` subcommand takes the same optional PR references
(`123`, `#123`, or a PR URL) and, given none, falls back to the current
branch's PR. Each one expands the set with the open backports of every seed, so
sibling PRs stay in lockstep without you tracking them by hand.

```bash
ci_fb review prs        # resolve and print the PR set this loop will drive
```

## Contracts this skill obeys

Defined in `AGENTS.md` — read there, not here:

- "PR review rules" — never merge; stop at ` [ready]`; triage every Copilot
  finding; propagate a valid finding to every sibling backport.
- "CI cost and skip labels" — what the labels mean and when to apply them.
- "Agent collaboration rules" — staging and commit-message rules for every fix
  this loop pushes.

`skip_all` is this loop's pause button and nothing else. `ci_fb review pause`
adds it, `ci_fb review resume` removes it, and `ci_fb review ready` refuses to
tag a PR that still carries it — a paused PR has no CI signal, so it cannot be
ready by definition.

## Procedure

### 1. Pause CI

```bash
ci_fb review pause
```

Adds `skip_all`, strips any ` [ready]` tag (a paused PR is not ready), and
cancels the PR's in-progress runs to free the runners.

### 2. Self-review the diff before asking for a machine review

Read and follow the **code-quality-review** skill
(`.github/skills/code-quality-review/SKILL.md`) on the current branch's diff.

Do this **before** step 3, not after. Copilot reviews the lines that exist when
it is asked; if a structural fix is still coming, its findings land on code that
is about to disappear, and you spend a round-trip answering threads on dead
lines.

- Apply the findings you agree with.
- On a sibling backport set, run it once on the originating PR and carry the
  same fixes across — the diffs are meant to stay identical.
- An empty report is a normal outcome. Do not manufacture a refactor to justify
  the step.

Skip this step only for a diff that cannot have structure: a lockfile bump, a
`renovate` update, a one-line constant change.

### 3. Request a Copilot review

Some repos auto-request Copilot on every push (branch ruleset "Review new
pushes") — there, a push is enough. To request explicitly, pass the bot **login**
(a display name like "Copilot" will not resolve):

```bash
for n in $(ci_fb review prs); do
  gh pr edit "$n" --add-reviewer copilot-pull-request-reviewer
done
```

If that fails because the reviewer is not requestable in this repo, rely on
auto-review on push or request it from the GitHub UI. Do not spin here.

### 4. Wait for the review to land

```bash
ci_fb review state
```

Prints one `PR #<n> <STATE>` line per PR. `COMMENTED` / `CHANGES_REQUESTED` /
`APPROVED` mean the review landed — go to step 5. `NONE` or `PENDING` means it
has not: **stop and re-check later**, do not proceed with nothing to triage.
This is a single non-blocking check, never a busy-wait. If it stays `NONE` well
past the usual few minutes, the request never landed — see step 3.

### 5. Read and triage every finding

```bash
ci_fb review findings
```

Prints Copilot's review summary and every inline finding, per PR, with the
comment id you need to reply. Human review threads are deliberately excluded —
they are for the humans; do not auto-reply to them.

For each Copilot finding:

- **Fix it in code** with the minimal correct change, **or**
- **Reply on that specific thread** explaining why it is intentionally not
  addressed:
  `gh api /repos/<owner>/<repo>/pulls/<n>/comments/<comment_id>/replies -f body=...`
- Never silently ignore a finding.
- Leave thread **resolution** to the human author.

### 6. Push fixes, then re-review

Commit under the staging and message rules in `AGENTS.md`. Then re-request the
review (step 3) and return to step 4. **Loop steps 3–6 until the newest Copilot
review adds no new actionable findings.**

### 7. Relaunch the tests

```bash
ci_fb review resume --rerun
```

Removes `skip_all` and re-runs each PR's latest completed run. The rerun is
needed because removing a label is not a workflow trigger; pushing a fix
re-triggers them too, in which case plain `ci_fb review resume` is enough.

The rerun is deliberately *full*, not `--failed`: the heavy jobs were skipped
while paused, not failed, so there is nothing for `--failed` to select.

### 8. Watch the tests

Use the **ci-feedback-loop** procedure (`.github/skills/ci-feedback-loop/SKILL.md`)
— `ci_fb locate` / `summarize` / `logs` / `artifacts`.

### 9. On failure → fix → re-enter the loop

- Map the failure to its source, read it, apply the **minimal real fix**.
- To re-run only the failed jobs of a completed run: `gh run rerun --failed <run-id>`.
- Never edit a workflow just to skip a check to go green.
- Then go back to **step 1**: `pause` is idempotent and strips the ` [ready]`
  tag again, since the regression made the PR not-ready.

### 10. On success → append the ` [ready]` tag

```bash
ci_fb review ready
```

Appends ` [ready]` once, at the end of each title. It refuses while `skip_all`
is still on the PR or while any check is failing or pending, so a green,
un-paused PR is a precondition rather than a thing you remember to verify.

**This is where the loop stops.** Tagging is the signal; merging is the human's.

## Anti-patterns

- **Don't merge.** This skill stops at the ` [ready]` tag.
- **Don't** request the Copilot review before step 2 — findings on code you are
  about to restructure are wasted round-trips.
- **Don't** silently drop a Copilot finding — fix it or reply with a rationale.
- **Don't** skip/disable a failing check to force green — fix the root cause.
- **Don't** reach for `--force` on `ci_fb review ready`. It exists for a human
  who knows why a check is red; an agent using it is lying about the state.
- **Don't** block the session on long polls — re-check later.

## References

- [ci-feedback-loop](../ci-feedback-loop/SKILL.md) — the CLI: CI status/logs/artifacts and the `review` subcommands.
- [code-quality-review](../code-quality-review/SKILL.md) — the strict self-review run at step 2.
- `AGENTS.md` → "PR review rules", "CI cost and skip labels", "Agent collaboration rules".

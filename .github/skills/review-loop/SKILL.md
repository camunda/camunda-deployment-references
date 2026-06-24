---
name: review-loop
description: 'Drive one or more pull requests to a review-ready state by pausing CI, requesting a GitHub Copilot review, fixing every finding, re-requesting until the review is clean, then re-running the tests and appending the exact ` [ready]` tag (leading space) to the end of the PR title. USE WHEN: the user invokes "/review-loop", or says "pause the CI and get a Copilot review", "run the review loop", "fix what Copilot says and re-review", "drive this PR to ready", "mets le PR en ready". INVOKES: gh CLI (pr/api/run), the ci-feedback-loop skill for test triage. DO NOT USE FOR: merging PRs, or one-off log fetching (use ci-feedback-loop directly).'
argument-hint: '[pr-number|pr-url ...] (defaults to the current branch PR + its backport PRs)'
---

# PR Review Loop

Autonomously drive a PR (and its sibling backport PRs) through this loop:

```
pause CI → request Copilot review → fix every finding → re-review (loop until clean)
        → relaunch tests → on failure: fix + re-enter loop → on success: tag [ready]
```

The goal is a PR that is green and has no outstanding Copilot findings, marked
ready for human review — **without ever merging it**.

## When to use

- The user wants a hands-off "get this PR reviewed and green" cycle.
- A change spans a main PR + one or more `backport-*-to-stable/*` PRs that must stay in sync.

## Prerequisites

- `gh` authenticated (`gh auth status`) with `pull-requests: write`.
- Working dir inside the target repo; the feature branch is pushed.
- You know the PR number(s). Backports are discovered automatically (step 0).

## Repo conventions (camunda-deployment-references)

- **Pause CI**: the `skip_all` label. `internal-triage-skip` ensures every skip
  label exists — both the per-workflow `skip_<workflow>` labels (built from
  workflow filenames) and `skip_all` — so it is already present; never
  hand-create skip labels. Every triage-guarded workflow honours `skip_all` and
  skips its heavy jobs while you iterate.
- **Ready marker**: a trailing ` [ready]` tag at the **end** of the PR **title**
  (e.g. `fix(ci): ... [ready]`) — appended, never a prefix.
- **Copilot reviewer**: `copilot-pull-request-reviewer[bot]`.
- **Findings**: inline review comments via
  `gh api /repos/<owner>/<repo>/pulls/<n>/comments`; thread state via the
  GraphQL `reviewThreads` field.
- **Backport rule** (AGENTS.md): a valid Copilot finding on one branch is valid
  on all — propagate the fix + thread reply to every sibling backport PR.
- Resolve `<owner>/<repo>` once: `REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)`.

## Procedure

### 0. Identify the target PR set

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
# Explicit args win — accept one or more PR numbers (`123` or `#123`) and/or
# PR URLs; otherwise fall back to the current-branch PR. Reduce each arg to the
# first numeric group (strip any `.../pull/` prefix first so the PR number wins):
if [ "$#" -gt 0 ]; then
  seeds=""
  for a in "$@"; do
    num=$(printf '%s' "$a" | sed -E 's#.*/pull/##' | grep -oE '[0-9]+' | head -1)
    [ -n "$num" ] && seeds="$seeds $num"
  done
else
  seeds=$(gh pr view --json number -q .number)
fi
# Discover sibling backports of EACH seed: the backport workflow writes
# "Backport of #<PR>" into each backport's body, so match on that (a title
# search like `backport in:title` would catch unrelated backports repo-wide).
PRS="$seeds"
for PR in $seeds; do
  PRS="$PRS $(gh pr list --repo "$REPO" --state open \
    --search "in:body \"Backport of #$PR\"" --json number -q '.[].number')"
done
# De-duplicate into the final set to drive (seeds + their backports):
PRS=$(printf '%s\n' $PRS | awk 'NF' | sort -un | tr '\n' ' ')
```

This yields `$PRS`, the full set to drive (originating PR + applicable
backports). The snippets in the steps below each iterate over `$PRS`, so run
them in the same shell session; keep the code changes identical across sibling
backports where the code exists on both branches.

### 1. Pause CI

```bash
for n in $PRS; do
  gh pr edit "$n" --repo "$REPO" --add-label skip_all
  # Free the runners: cancel this PR's in-progress runs on its own head branch.
  head_ref=$(gh pr view "$n" --repo "$REPO" --json headRefName -q .headRefName)
  gh run list --repo "$REPO" --branch "$head_ref" --status in_progress \
    --json databaseId -q '.[].databaseId' | xargs -r -n1 gh run cancel --repo "$REPO"
done
```

`skip_all` makes the triage job report `should_skip=true`, so subsequent runs
skip the heavy jobs while you iterate.

### 2. Request a Copilot review

Some repos auto-request Copilot on every push (branch ruleset "Review new
pushes") — in that case a push is enough. To request explicitly:

```bash
for n in $PRS; do
  # Preferred (recent gh): add the Copilot reviewer by its login. A display name
  # like "Copilot" will not resolve — `gh pr edit` expects the bot login.
  gh pr edit "$n" --repo "$REPO" --add-reviewer copilot-pull-request-reviewer 2>/dev/null \
    || {
      # Fallback: GraphQL requestReviews with the Copilot bot id (note: the
      # reviewer bot is not in suggestedActors on every repo, so this can be empty).
      PR_ID=$(gh pr view "$n" --repo "$REPO" --json id -q .id)
      BOT_ID=$(gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){suggestedActors(capabilities:[CAN_BE_ASSIGNED],first:100){nodes{login __typename ... on Bot{id} ... on User{id}}}}}' \
        -f o="${REPO%/*}" -f r="${REPO#*/}" \
        --jq '.data.repository.suggestedActors.nodes[] | select(.login=="copilot-pull-request-reviewer") | .id')
      if [ -z "$BOT_ID" ]; then
        echo "Copilot reviewer not assignable here (absent from suggestedActors); " \
             "rely on auto-review on push, or request it from the GitHub UI." >&2
      else
        gh api graphql -f query='mutation($p:ID!,$b:ID!){requestReviews(input:{pullRequestId:$p,botIds:[$b],union:true}){pullRequest{id}}}' \
          -f p="$PR_ID" -f b="$BOT_ID"
      fi
    }
done
```

### 3. Wait for the review to land

Poll (non-blocking — re-check later, do not hang the session) until the Copilot
review is present and **no longer pending**:

```bash
for n in $PRS; do
  printf 'PR #%s: ' "$n"
  gh pr view "$n" --repo "$REPO" --json reviews \
    --jq '[.reviews[] | select(.author.login=="copilot-pull-request-reviewer")] | last | .state // "NONE"'
done
```

A Copilot run typically takes a few minutes. Treat states
`COMMENTED` / `CHANGES_REQUESTED` / `APPROVED` as "done"; `PENDING` means keep waiting.

### 4. Read and triage every finding

```bash
for n in $PRS; do
  gh api "/repos/$REPO/pulls/$n/comments" \
    --jq '.[] | {id, path, line, body, user: .user.login, in_reply_to: .in_reply_to_id}'
done
```

Read **every inline finding**, not just the review summary. For each finding:

- **Fix it in code** with the minimal correct change, **or**
- **Reply on that specific thread** explaining why it is intentionally not
  addressed (`gh api /repos/$REPO/pulls/$n/comments/<comment_id>/replies -f body=...`).
- Never silently ignore a finding.
- **Propagate** any code fix + reply to every sibling backport PR where the same
  code exists.
- Leave thread **resolution** to the human author; do not resolve threads yourself.

### 5. Push fixes, then re-review

```bash
git add -u && git commit -m "fix(<scope>): address Copilot review" && git push
```

Re-request the review (step 2) and return to step 3. **Loop steps 2–5 until the
newest Copilot review adds no new actionable findings** (only resolved threads /
"looks good" remain).

### 6. Relaunch the tests

```bash
for n in $PRS; do gh pr edit "$n" --repo "$REPO" --remove-label skip_all; done
```

Removing `skip_all` alone does not re-trigger workflows (the `unlabeled` event
is not in the triggers). Start fresh runs — per PR, on its own head branch — by
re-running the latest run (now that triage will no longer skip), or just push:

```bash
for n in $PRS; do
  head_ref=$(gh pr view "$n" --repo "$REPO" --json headRefName -q .headRefName)
  gh run list --repo "$REPO" --branch "$head_ref" \
    --json databaseId -q '.[0].databaseId // empty' | xargs -r -n1 gh run rerun --repo "$REPO"
done
# or, if there is a fix to push, the push already re-triggers them.
```

### 7. Watch the tests

Use the **ci-feedback-loop** skill (`.github/skills/ci-feedback-loop/SKILL.md`)
for non-blocking status, focused logs, and artifacts — read it and follow its
`locate` / `summarize` / `logs` / `artifacts` procedure.

### 8. On failure → fix → re-enter the loop

- Map the failure to its source, read it, apply the **minimal real fix**.
- Never edit a workflow just to skip a check to go green.
- Then go back to **step 1** (pause CI, re-review the fix, …). The loop repeats
  until tests are green **and** Copilot has no findings.

### 9. On success → append the [ready] tag

Once tests are green and no Copilot findings remain, append a ` [ready]` tag to
the **end** of the title (idempotently — never double-tag), for each PR:

```bash
for n in $PRS; do
  title=$(gh pr view "$n" --repo "$REPO" --json title -q .title)
  case "$title" in
    *" [ready]") ;;                                         # already ready
    *) gh pr edit "$n" --repo "$REPO" --title "$title [ready]" ;;
  esac
done
```

Confirm `skip_all` is removed before declaring done.

## Anti-patterns

- **Don't merge.** This skill stops at the ` [ready]` tag.
- **Don't** silently drop a Copilot finding — fix it or reply with a rationale.
- **Don't** skip/disable a failing check to force green — fix the root cause.
- **Don't** leave `skip_all` on a PR you just marked ready.
- **Don't** prefix or double-tag `[ready]` — it is appended once, at the end.
- **Don't** block the session on long polls — re-check later.

## References

- [ci-feedback-loop](../ci-feedback-loop/SKILL.md) — CI status/logs/artifacts.
- `AGENTS.md` → "PR review rules" — the Copilot-triage + backport-propagation contract.

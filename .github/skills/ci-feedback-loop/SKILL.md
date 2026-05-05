---
name: ci-feedback-loop
description: 'Iterate on a feature by fetching GitHub Actions CI logs, statuses, and artifacts to debug failures locally. USE WHEN: a PR has failing CI checks, the user asks to "debug CI", "fix the pipeline", "why is the test failing in CI", "fetch the CI logs", "check the CI", or wants to set up a fix-push-recheck loop. INVOKES: gh CLI (run list/view/download), local zip/json parsing. DO NOT USE FOR: triggering new runs, modifying workflows themselves, or general code review.'
argument-hint: '[run-id|--latest|--watch] (optional)'
---

# CI Feedback Loop

Pull failing GitHub Actions context (status → failed jobs → step logs → artifacts) into the local working session so the agent can fix issues without round-tripping through the GitHub UI.

A small Go CLI (in this skill folder) wraps the `gh` CLI for orchestration, parses logs/artifacts, and writes everything under `debug/ci/<run_id>/` — the `debug/**` path is already covered by `.gitignore`.

## When to Use

- A PR is open and one or more workflow runs failed
- User asks to "debug CI", "check the pipeline", "fix the failing tests in CI", "fetch the CI logs"
- Iterating on a feature branch where commits keep breaking specific jobs
- Need cluster-state artifacts (kubectl dumps, helm logs, pod descriptions) attached to a failed run

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- `go` ≥ 1.23 on `PATH`
- Working directory inside the target git repo on the feature branch

## Setup

The CLI lives in [`.github/skills/ci-feedback-loop`](./) as its own Go module. Invoke it with the helper alias (run once per shell):

```bash
ci_fb() { (cd "$(git rev-parse --show-toplevel)/.github/skills/ci-feedback-loop" && go run . "$@"); }
```

Then use `ci_fb <subcommand>` from anywhere in the repo. All examples below assume this alias is defined.

Available subcommands: `locate`, `summarize`, `logs`, `artifacts`. Pass `--help` to any of them for flags.

## Procedure

### 1. Locate the target run

```bash
ci_fb locate                       # list 10 most recent runs (non-blocking)
ci_fb locate --latest              # print only the latest RUN_ID (non-blocking)
ci_fb locate <RUN_ID>              # print this RUN_ID (non-blocking)
ci_fb locate --wait                # block until every in-progress run finishes (hard timeout)
ci_fb locate --latest --wait       # wait, then print the latest RUN_ID
ci_fb locate <RUN_ID> --wait       # wait specifically on this run
```

**Default is non-blocking** — listing returns immediately and flags any pending runs in the footer (`⏳ N run(s) still in progress`). The agent should re-invoke later rather than blocking the conversation.

When `--wait` is set, the command polls every 30 s without streaming logs, and aborts with a clear message after `--wait-timeout` seconds (default `1800` = 30 min). This prevents the calling agent from hanging.

The command emits a single `RUN_ID=<id>` line on stdout when resolved (with `--latest` or an explicit id). Capture it for later steps.

### 2. Summarize failures

```bash
ci_fb summarize <RUN_ID>
```

Prints workflow metadata + only the **failed/cancelled jobs** with their failing step numbers. Compact enough to keep in context — use it to decide which logs/artifacts to pull next.

### 3. Fetch focused logs

```bash
ci_fb logs <RUN_ID> [--job <substring>] [--tail 200] [--context 80]
```

Behavior:
- Downloads the run's full log archive once into `debug/ci/<RUN_ID>/_run.zip`
- Extracts to `debug/ci/<RUN_ID>/logs/`
- For each failed job (optionally filtered by `--job`), prints:
  - the **last `--tail` lines** of its log
  - the **first error context** (regex `error|fail|fatal|panic`, ±lines, capped at `--context` lines)

Read the printed excerpts directly. Open `debug/ci/<RUN_ID>/logs/<job>.txt` only if excerpts are insufficient.

### 4. Download artifacts (cluster state, etc.)

```bash
ci_fb artifacts <RUN_ID>                       # list only
ci_fb artifacts <RUN_ID> --name cluster-dump   # download matching
```

Stored under `debug/ci/<RUN_ID>/artifacts/<name>/`. Always list first, pick by name (e.g. `cluster-dump`, `pod-logs-kind`, `helm-status`), then download.

After download, inspect the most useful files:
- `*.yaml` / `*.json` — read directly
- `*.log` / `*.txt` — `tail` or `grep` for the error keywords from step 2
- `*.tar.gz` / `*.zip` — extract in place before reading

### 5. Diagnose and fix

With logs + artifacts in `debug/ci/<RUN_ID>/`:
1. Map the error message to the source (workflow step, action, script, app code)
2. Read that source file before editing
3. Apply the minimal fix
4. Verify locally if possible (lint, unit test, dry-run)

### 6. Push and re-loop

```bash
git add -u && git commit -m "fix(ci): <short description>" && git push
# Either: poll later non-blockingly
ci_fb locate
# Or: explicitly wait (safe — hard timeout)
ci_fb locate --latest --wait
```

Repeat steps 2–6 until the pipeline is green.

## Cleanup

`debug/**` is gitignored. Delete anytime: `rm -rf debug/ci`.

## Anti-patterns

- **Don't** dump full logs into the conversation. Use `summarize` + `logs` excerpts.
- **Don't** download every artifact blindly — list first, then pick by `--name`.
- **Don't** push-and-pray. Always re-watch the run after fixing.
- **Don't** edit the workflow YAML to "skip" a check just to make CI pass — fix the underlying issue.

## References

- [main.go](./main.go) — the full CLI (cobra subcommands)
- [go.mod](./go.mod)

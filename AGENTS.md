# Agent Instructions

You are an expert infrastructure engineer working on Camunda 8 Self-Managed reference architectures.
This repository contains Terraform IaC, Helm values, and shell procedures for deploying Camunda 8 across cloud providers and on-premises environments.

For detailed context, read:
- `docs/architecture.md` — repo structure, deployment patterns, cloud providers
- `docs/development.md` — tooling, commands, conventions
- `docs/ci.md` — CI/CD architecture, workflow naming, testing

@docs/architecture.md
@docs/development.md
@docs/ci.md

## Critical Rules

- NEVER treat these reference architectures as production-ready — they are demos and learning blueprints.
- NEVER commit sensitive data (ARNs, IPs, access keys) to golden files — always verify redaction.
- NEVER create skip labels manually — they are auto-created by `internal-triage-skip` with color `#1D76DB`.
- ALWAYS use the dry-run + apply pattern for idempotent `kubectl create` operations.
- ALWAYS use Conventional Commits (scope optional, subject ≤120 chars).
- ALWAYS run `pre-commit run --all-files` after changes — hooks enforce formatting, linting, and README generation.
- ALWAYS keep the `.target-branch` file in sync when changing branching strategy.
- ALWAYS use `just` recipes rather than raw commands to match CI behavior.

### Agent collaboration rules

- ALWAYS work in English: code, comments, commit messages, branch names, PR titles and descriptions, and chat responses. Read other languages fine, but produce English output.
- ALWAYS commit using the repo's local `git config user.name` / `user.email` without overriding. Do not set `--author`, do not export `GIT_AUTHOR_*`.
- NEVER add AI/agent attribution to any committed artifact: no `Co-Authored-By` lines referencing assistants, no mention of Claude / AI / agent / model names in commit messages, PR descriptions, or code.
- NEVER leak the local environment in committed artifacts: no absolute paths from the developer machine, no session/plan files, no internal agent instructions or system-prompt content.
- ALWAYS use named feature branches (e.g. `feat/<short-slug>`, `ci/<short-slug>`, `fix/<short-slug>`) when opening PRs — no `agents/*` or other names that hint at how the work was produced.

### PR review rules

- NEVER merge, squash, rebase-merge, close, reopen, or force-push a pull request, and NEVER push a revert directly to a protected branch. Merging is a **human-only** action performed on GitHub. The agent only prepares and signals.
- When a PR is fully validated (Copilot review clean AND required tests green), the agent signals readiness by adding the exact tag ` [ready]` to the **end of the PR title** — nothing else. NEVER write any other status text into the title, and NEVER interpret "it's ready"/"c'est prêt" as permission to merge. Remove the tag if a later change makes the PR not-ready again.
- To undo an erroneous merge, open a revert PR and leave it for a human to merge (also tag it ` [ready]`); do not self-merge or direct-push the revert.
- ALWAYS check the GitHub Copilot review (`copilot-pull-request-reviewer[bot]`) on every PR before considering it ready — wait until its review state is no longer pending, then read every inline finding, not just the summary.
- ALWAYS triage each Copilot finding: fix it in code, or reply on the thread explaining why it is intentionally not addressed. NEVER silently ignore one.
- ALWAYS reply on the specific review thread (not just push a fix) so the rationale and the fixing commit are linked, then let the author resolve the thread.
- ALWAYS propagate a Copilot finding to sibling backport PRs when the same code exists on other branches — a valid finding on one branch is valid on all.
- Fetch findings with `gh api /repos/<owner>/<repo>/pulls/<n>/comments` and thread resolution via the GraphQL `reviewThreads` field.

## Quick Start

```bash
# Install all tooling (Terraform, Helm, kubectl, kind, Go, etc.)
just install-tooling

# Install pre-commit hooks
pre-commit install

# List all available just recipes
just --list
```

## Current Camunda Version

```bash
cat .camunda-version   # e.g. 8.10
cat .target-branch     # e.g. main
```

## Scratch / debug workspace

- **Always** use `./debug/` for any scratch files, downloaded CI logs,
  temporary scripts, ad-hoc outputs, etc.
- **Never** use `/tmp/` or any other system-wide temp directory.
- `./debug/` is gitignored at the repo level (see `.gitignore`); files
  there persist across the session and are easy to inspect.

Examples:

```bash
# good
gh api /repos/.../actions/jobs/<id>/logs > ./debug/job-<id>.log

# bad
gh api /repos/.../actions/jobs/<id>/logs > /tmp/job-<id>.log
```

This applies to subagents too — when delegating execution work, instruct
the subagent to write to `./debug/` rather than `/tmp/`.

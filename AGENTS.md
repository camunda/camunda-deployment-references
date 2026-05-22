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

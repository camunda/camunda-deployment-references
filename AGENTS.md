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

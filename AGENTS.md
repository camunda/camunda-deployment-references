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
- ALWAYS apply `skip_` labels for the cloud suites a change cannot affect — see "CI cost and skip labels".
- ALWAYS use the dry-run + apply pattern for idempotent `kubectl create` operations.
- ALWAYS use Conventional Commits (scope optional, subject ≤120 chars).
- ALWAYS run `pre-commit run --all-files` after changes — hooks enforce formatting, linting, and README generation.
- ALWAYS keep the `.target-branch` file in sync when changing branching strategy.
- ALWAYS use `just` recipes rather than raw commands to match CI behavior.

### Agent collaboration rules

- ALWAYS work in a dedicated session worktree under `debug/wt-<slug>` — never edit the main checkout (see "Session worktrees" below).
- ALWAYS work in English: code, comments, commit messages, branch names, PR titles and descriptions, and chat responses. Read other languages fine, but produce English output.
- ALWAYS commit using the repo's local `git config user.name` / `user.email` without overriding. Do not set `--author`, do not export `GIT_AUTHOR_*`.
- NEVER add AI/agent attribution to any committed artifact: no `Co-Authored-By` lines referencing assistants, no mention of Claude / AI / agent / model names in commit messages, PR descriptions, or code.
- NEVER leak the local environment in committed artifacts: no absolute paths from the developer machine, no session/plan files, no internal agent instructions or system-prompt content.
- ALWAYS use named feature branches (e.g. `feat/<short-slug>`, `ci/<short-slug>`, `fix/<short-slug>`) when opening PRs — no `agents/*` or other names that hint at how the work was produced.

### CI cost and skip labels

Every cloud test workflow is gated by `internal-triage-skip`: a `skip_<filename_without_ext>`
label on the pull request makes that workflow skip all of its jobs, and `skip_all` skips
every one of them. `aws_openshift_rosa_hcp_single_region_tests.yml` is therefore skipped by
`skip_aws_openshift_rosa_hcp_single_region_tests` — see `docs/ci.md`, "Workflow Naming".
The action posts a checklist comment listing the available options and creates the labels
itself.

These suites provision real infrastructure — EKS, ROSA, Aurora, OpenSearch, NAT gateways —
and take tens of minutes. A suite the change cannot affect proves nothing, bills the CI
account, and delays the feedback loop. Skipping it is a velocity gain, not a shortcut.

- ALWAYS pick the skip labels when opening a pull request, and revisit them whenever the
  diff grows. Compare the diff against each workflow's `paths:` filter: a shared path such
  as `.github/actions/**` fans a CI-plumbing change out to every cloud suite at once.
- ALWAYS keep the suites that cover the change itself. A port-forward fix needs the
  workflows that port-forward; a Terraform change needs the reference architecture it
  touches.
- When in doubt, skip. Removing the label re-runs the suite on the next push, so the
  decision is cheap to reverse — say on the pull request which suite was skipped and why.
- ALWAYS re-enable, in the final review loop, every suite that covers the change, and let
  it run green on the final commit. NEVER add the ` [ready]` tag while a suite covering the
  change is still skipped.
- ALWAYS apply `skip_all` to a pull request that is parked, blocked on a conflict, or a
  draft nobody is actively testing. Remove it when the work resumes.

### PR review rules

- NEVER merge, squash, rebase-merge, close, reopen, or force-push a pull request, and NEVER push a revert directly to a protected branch. Merging is a **human-only** action performed on GitHub. The agent only prepares and signals.
- When a PR is fully validated (Copilot review clean AND required tests green), the agent signals readiness by adding the exact tag ` [ready]` to the **end of the PR title** — nothing else. NEVER write any other status text into the title, and NEVER interpret "it's ready"/"c'est prêt" as permission to merge. Remove the tag if a later change makes the PR not-ready again.
- To undo an erroneous merge, open a revert PR and leave it for a human to merge (also tag it ` [ready]`); do not self-merge or direct-push the revert.
- ALWAYS check the GitHub Copilot review (login `copilot-pull-request-reviewer`, rendered `copilot-pull-request-reviewer[bot]` as a review author) on every PR before considering it ready — wait until its review state is no longer pending, then read every inline finding, not just the summary.
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

## Session worktrees

Multiple agent sessions and the human share the same clone. Working directly in
the main checkout means concurrent sessions fight over the same files, the same
index, and the same checked-out branch — and a `git checkout` in one session
silently breaks the others.

- **Always** create a dedicated worktree for the session before the first edit:

  ```bash
  # from the main checkout, branching off the target branch
  git worktree add -b feat/<short-slug> debug/wt-<slug> "$(cat .target-branch)"
  ```

- **Always** run every command — `just`, `terraform`, `pre-commit`, `git`, `gh` —
  from inside `debug/wt-<slug>`, never from the main checkout.
- **Never** `git checkout` / `git switch` / `git stash` / `git reset` in the main
  checkout to make room for the work.
- One worktree per session, one branch per worktree. The same branch cannot be
  checked out twice; run `git worktree list` first to reuse an existing one.
- Worktrees live under `debug/` because it is gitignored (see `.gitignore`), so
  they are invisible to `pre-commit run --all-files`, `terraform fmt -recursive`
  and the README generators running in the parent checkout.
- Backports: one worktree per target branch, e.g. `debug/wt-<slug>-8.8` tracking
  `stable/8.8` — never reuse a single worktree across branches.
- Clean up once the PR is merged or abandoned (from the main checkout):

  ```bash
  git worktree remove debug/wt-<slug> && git worktree prune
  ```

  Keep the worktree while the PR is open (review fixes, rebases). **Never**
  remove a worktree the session did not create.
- Scratch files still go to the worktree's own `debug/` directory, which is
  gitignored there too.

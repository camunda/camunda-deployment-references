# Agent Conventions

<<<<<<< HEAD
## CI cost and skip labels
=======
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
- ALWAYS stage only the paths the change touched — `git add -- <paths>`, NEVER `git add -u` / `git add .`. The working tree carries `debug/` scratch, downloaded CI logs and session worktrees; a blanket stage sweeps them into a public commit. Confirm with `git status --short` before committing.
- ALWAYS write a real scope and subject — never a literal placeholder such as `fix(ci): <short description>`. Commitlint's scope allowlist (`[a-z0-9-]+`) rejects angle brackets, and a placeholder makes `git log` unauditable.
- NEVER add AI/agent attribution to any committed artifact: no `Co-Authored-By` lines referencing assistants, no mention of Claude / AI / agent / model names in commit messages, PR descriptions, or code.
- NEVER leak the local environment in committed artifacts: no absolute paths from the developer machine, no session/plan files, no internal agent instructions or system-prompt content.
- ALWAYS use named feature branches (e.g. `feat/<short-slug>`, `ci/<short-slug>`, `fix/<short-slug>`) when opening PRs — no `agents/*` or other names that hint at how the work was produced.

### CI cost and skip labels
>>>>>>> 9195308 (refactor(agents): one owner per rule across the agent surface [ready] (#3306))

Every cloud test workflow is gated by `internal-triage-skip`: a `skip_<filename_without_ext>`
label on the pull request makes that workflow skip all of its jobs, and `skip_all` skips
every one of them. `aws_openshift_rosa_hcp_single_region_tests.yml` is therefore skipped by
`skip_aws_openshift_rosa_hcp_single_region_tests` — see `DEVELOPER.md`, "Skipping Workflows
Using Labels". The action creates the labels itself; never hand-create one.

These suites provision real infrastructure — EKS, ROSA, Aurora, OpenSearch, NAT gateways —
and take tens of minutes. A suite the change cannot affect proves nothing, bills the CI
account, and delays the feedback loop. Skipping it is a velocity gain, not a shortcut.

- **Always** pick the skip labels when opening a pull request, and revisit them whenever
  the diff grows. Compare the diff against each workflow's `paths:` filter: a shared path
  such as `.github/actions/**` fans a CI-plumbing change out to every cloud suite at once.
- **Always** keep the suites that cover the change itself. A port-forward fix needs the
  workflows that port-forward; a Terraform change needs the reference architecture it
  touches.
- When in doubt, skip. Removing the label re-runs the suite on the next push, so the
  decision is cheap to reverse — say on the pull request which suite was skipped and why.
- **Always** re-enable, in the final review loop, every suite that covers the change, and
  let it run green on the final commit. **Never** mark a pull request ready while a suite
  covering the change is still skipped.
- **Always** apply `skip_all` to a pull request that is parked, blocked on a conflict, or a
  draft nobody is actively testing. Remove it when the work resumes.

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

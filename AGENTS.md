# Agent Conventions

## CI cost and skip labels

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

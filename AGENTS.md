# Agent Conventions

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

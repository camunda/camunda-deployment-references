# CI/CD Architecture

## Workflow Naming

### Filenames

Workflow filenames mirror the folder structure of the architecture they test:

```
{provider}_{category}_{solution}_{variant}_{type}.yml
```

**Abbreviation rules** (apply when the solution name implies the category):

| Long form | Short form |
|-----------|-----------|
| `aws_kubernetes_eks_` | `aws_eks_` |
| `aws_containers_ecs_` | `aws_ecs_` |
| `aws_openshift_rosa_hcp_` | `aws_rosa_hcp_` |
| `azure_kubernetes_aks_` | `azure_aks_` |
| `local_kubernetes_kind_` | `local_kind_` |

**Constraint:** The resulting skip label (`skip_<filename_without_ext>`) must be ≤ 50 characters (GitHub label limit). The `internal-triage-skip` action validates this at runtime and fails if exceeded.

### Display Names

```yaml
# Linting
name: Internal - Global - Lint

# Integration tests
name: Tests - Integration - AWS EKS Single Region

# Daily cleanup
name: Tests - Daily Cleanup - AWS EKS Single Region
```

Internal workflows are prefixed `internal_<scope>_<purpose>.yml` with display name `Internal - <Scope> - <Purpose>`.

## Workflow Structure

Every workflow must include a `triage` job with `internal-triage-skip`:

```yaml
triage:
  runs-on: ubuntu-latest
  outputs:
    should_skip: ${{ steps.skip_check.outputs.should_skip }}
  steps:
    - uses: actions/checkout@...
    - name: Check labels
      id: skip_check
      uses: ./.github/actions/internal-triage-skip

next-job:
  needs: [triage]
  if: needs.triage.outputs.should_skip == 'false'
```

Skip labels are auto-created by the action (color `#1D76DB`). Apply them at PR creation time; the first run will still trigger all workflows if the label is added afterward.

## Test Types

| Type | Description |
|------|-------------|
| Integration tests | Full infra creation → Camunda deploy → functional tests → destroy |
| Golden file tests | Terraform plan output compared against stored JSON fixtures |
| Daily cleanup | Scheduled destroy jobs to prevent orphaned cloud resources |
| Module unit tests | Go-based Terratest for `modules/` — fast, no real infra |

### Re-running a failed cloud workflow

Use a **full** re-run, not `gh run rerun --failed`.

The cloud integration workflows pass cluster coordinates from the `Prepare clusters` job to the test jobs as an encrypted artifact, decrypted downstream with `openssl enc -d`. A partial re-run does not regenerate that artifact consistently: the intermediate matrix-output job can succeed while carrying an empty payload from the previous attempt, and every downstream job then fails with

```
error reading input file
##[error]Process completed with exit code 1
```

followed by `kubernetes cluster unreachable`, which looks like a broken deployment but is a re-run artifact. Prefer:

```bash
gh run rerun <run-id>          # full re-run, regenerates every artifact
gh run rerun <run-id> --failed # avoid on cloud workflows
```

A full re-run reprovisions the clusters, so check the cloud quotas first when several runs are in flight.

### A push can lose its run

The long-running workflows, the integration suites and the daily cleanups, declare `concurrency.cancel-in-progress: false` so that a new run never cancels one that is still tearing infrastructure down. The cost is that a push landing while that group is busy can produce no run at all for that workflow: the ones that do cancel in progress, the golden-plan and lint workflows among them, appear on the new commit as usual, and the long-running one silently does not.

Check before assuming the workflow is broken:

```bash
gh api "/repos/<owner>/<repo>/actions/runs?head_sha=<sha>" --jq '.workflow_runs[].name'
```

There is nothing to fix in the workflow. Push again once the group is free, or re-run the previous run if its commit is still the one you want to test.

### Keeping a pull request to the tests it needs

Every workflow whose `paths` match anything in the pull request runs on every push, and the filter reads the whole pull-request diff rather than the last push. A branch that touches a shared action therefore provisions clusters for architectures it has nothing to do with.

`internal-triage-skip` is the way out. Label the pull request `skip_<workflow filename without extension>` and that workflow's triage job short-circuits the rest, so the run appears but no cluster is created:

```bash
gh pr edit <pr> --add-label skip_aws_openshift_rosa_hcp_dual_region_tests
```

Never create those labels by hand: `internal-triage-skip` creates them, with colour `#1D76DB`, and also posts a checklist comment offering the same choices as checkboxes.

### Inspecting a live cluster before the teardown

`aws_eks_multi_region_rdbms_tests.yml` stops on an SSH session after the tests and before the destroy step, on the runner that provisioned the clusters. Two switches turn it on, because a workflow has to be on the default branch before it can be dispatched:

```bash
# once the workflow is on the default branch
gh workflow run aws_eks_multi_region_rdbms_tests.yml -f debug_tmate=true

# until then, from the pull request
gh pr edit <pr> --add-label debug_tmate
```

The label is read from the event payload, so it has to be on the pull request before the run starts. Adding it does not trigger a run by itself; push, or re-run after a push that already carried it.

The connection string is printed in the step log and only the user who started the run can attach. The runner already holds a kubectl context per region, so `kubectl --context cluster-london get pods -n camunda` works without any setup. End the session with `touch /continue`, or leave it and the step expires after 30 minutes.

The AWS credentials come from a role assumed at the start of the job. They expire on their own schedule, so `kubectl` can stop working while the session is still open.

## CI Status Reporting

CI emits complementary operational signals:

- `internal_global_ci_events_reporter.yml` records workflow-run failures and warnings in a Google Sheet.
- `report-failure-on-slack` notifies the responsible Slack channel when a workflow fails.
- Onboarded jobs use `start-build-monitor` as their first step and `observe-build-status` as their final, non-blocking step to record status and duration in the `build_status_v2` BigQuery table. The action uses the workflow's existing Vault AppRole credentials to retrieve its upload key.

## Workflow Scheduling

Schedules are defined in `.github/workflows-config/workflow-scheduler.yml`. Tests are staggered by:
- Camunda version (8.7, 8.8, 8.9, 8.10)
- Day of week
- Time of day

This prevents GitHub Actions rate limit exhaustion when multiple branches run simultaneously.

## Custom Actions

All reusable CI logic lives in `.github/actions/`. Each action has:
- Docker-based or composite (shell script) implementation
- Auto-generated `README.md` (via `update-action-readmes-docker` pre-commit hook)

**Action categories:**
- `*-create` / `*-destroy` — provision/teardown cloud infrastructure
- `internal-*` — shared CI utilities (triage, drift detection, golden plans, matrix generation)
- `kubernetes-*` — Kubernetes-level setup (operators, ingress, certificates, DNS)
- `aws-cognito-create` / `aws-aurora-manage-cluster` / `aws-opensearch-manage-cluster` — cloud service setup

## GitHub Actions Conventions

- **Pin all actions to a commit SHA**, not a semver tag. Renovate handles updates automatically.
  ```yaml
  # Correct
  uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4
  # Wrong
  uses: actions/checkout@v4
  ```
- **All secrets come from Vault** — never GitHub Secrets or hardcoded values. CI secrets live at `secret/data/products/infrastructure-experience/ci/common` (AWS, Azure, common credentials).

## PR Automation

- **Auto-labeling:** `.github/labeler.yml` assigns labels based on changed paths (e.g. `aws/`, `azure/`, `generic/`)
- **Renovate:** `.github/renovate.json5` extends `github>camunda/infraex-common-config:default.json5`. This shared config governs scheduling (weekends only, except CVEs), grouping (minor+patch together), automerge, and custom regex managers for non-standard deps (ROSA, Helm chart versions). Update `baseBranchPatterns` when branches are added/removed.

## Customer-Facing Repo

`camunda-deployment-references` is a **customer-facing** repository. This means:
- PRs must be structured and well-described (motivation + implications)
- Documentation PRs in [camunda-docs](https://github.com/camunda/camunda-docs) should accompany significant changes
- Typical PR breakdown for a new reference architecture: (1) Terraform modules, (2) Helm values + procedures, (3) CI tests

## Release Process

1. Cut `stable/8.x` from `main`
2. Update `.camunda-version` to the new version
3. Update `.target-branch` to point to `stable/8.x`
4. Add schedules for the new version in `workflow-scheduler.yml`
5. Prepare `main` for next version: bump `dev-latest` tag, update Renovate regex patterns
6. Update `renovate.json5` `baseBranchPatterns` to include new stable branch
7. Resolve all `TODO [release-duty]` markers in the codebase

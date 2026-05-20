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

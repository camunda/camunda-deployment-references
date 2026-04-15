# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A collection of reference architectures for deploying **Camunda 8 self-managed** across cloud providers (AWS, Azure) and runtimes (EKS, ECS/Fargate, AKS, ROSA HCP, EC2). These are copy-paste-ready Terraform blueprints—educational and demonstrative, not production-hardened. The current dev version targets Camunda **8.9** on `main`; stable branches exist for `stable/8.6`, `stable/8.7`, `stable/8.8`.

## Commands

**Tooling** (install via [asdf](https://asdf-vm.com/), managed by `.tool-versions`):
```bash
just install-tooling        # Install all tools via asdf
```

**Linting** (runs automatically via pre-commit hooks):
```bash
pre-commit install          # Install git hooks (run once)
pre-commit run --all-files  # Run all checks manually
```

**AWS module tests** (Go + Terratest, from `aws/modules/.test/src/`):
```bash
just aws-tf-modules-tests                    # All tests in parallel (via gotestsum)
just aws-tf-modules-test TestName            # Single test by name
just aws-tf-modules-test-verbose TestName    # Single test, verbose output
```

Required env vars for tests:
```bash
export TF_STATE_BUCKET="<s3-bucket>"
export TF_STATE_BUCKET_REGION="eu-central-1"
export TESTS_CLUSTER_REGION="eu-west-1"
export CLEAN_CLUSTER_AT_THE_END=false        # Keep infra after test failure for debugging
```

**Golden files** (Terraform plan snapshots for regression detection):
```bash
just regenerate-golden-file <module_dir> <backend_region> <bucket_name> <bucket_key>
just regenerate-golden-file-all              # Regenerate all (requires TFSTATE_BUCKET + TFSTATE_REGION)
```

## Architecture

### Directory layout

```
aws/
  compute/          # EC2-based deployments
  containers/       # ECS Fargate deployments
  kubernetes/       # EKS (single and dual-region)
  openshift/        # ROSA HCP
  modules/          # Reusable AWS Terraform modules + Terratest suite
  common/           # Shared utilities (Cognito, etc.)
azure/
  kubernetes/       # AKS
  modules/          # Reusable Azure Terraform modules
  common/
generic/
  kubernetes/       # Cloud-agnostic K8s (operator/Helm-based)
  openshift/
local/
  kubernetes/kind-single-region/  # Local dev with KinD
```

Each solution follows the pattern: `{cloud}/{category}/{solution}/{variation}/` (e.g., `aws/kubernetes/eks-single-region/terraform/`). Within each solution:
- `terraform/clusters/` — the deployable Terraform root module
- `terraform/modules/` — solution-local modules
- `test/golden/` — golden file snapshots + `.tfvars` fixture
- `test/fixtures/golden/` — `fixture_*.tf` files temporarily copied in during golden file generation

### Module reuse

`aws/modules/` and `azure/modules/` contain reusable Terraform modules (eks-cluster, aurora, opensearch, ecs fargate, AKS, etc.) consumed by solutions in the same cloud provider tree. The Terratest suite at `aws/modules/.test/src/` tests these modules by spinning up real cloud resources.

### Testing strategy

- **Pre-commit hooks**: `terraform_fmt`, `terraform_tflint`, `terraform_docs`, `trivy-scan`, `yamllint`, `shellcheck`, `go-mod-tidy`, `actionlint-docker`
- **Golden files**: Terraform plan output serialized to `test/golden/tfplan-golden.json`, ARNs and versions redacted for stable diffs. Detect unintended infra changes before merging.
- **Integration tests**: Terratest (`aws/modules/.test/src/*_test.go`) creates real AWS resources. Skip via commit message (`skip-tests:TestName1,TestName2` or `skip-tests:all`) or PR label.

### CI/CD conventions

Workflow filenames follow the folder path of the tested architecture: `aws/openshift/rosa-hcp-single-region` → `aws_openshift_rosa_hcp_single_region_tests.yml`. Abbreviation rules apply when the service implies the category (e.g., `aws_containers_ecs_` → `aws_ecs_`, `aws_kubernetes_eks_` → `aws_eks_`). This is **not stylistic**—the skip label `skip_<workflow_name>` must be ≤50 characters (GitHub limit). The `internal-triage-skip` action enforces this at runtime.

Workflow `name:` field format:
- `Internal - Global - Lint`
- `Tests - Integration - AWS OpenShift ROSA HCP Single Region`
- `Tests - Daily Cleanup - AWS ECS Single Region`

All workflows must include a `triage` job using `.github/actions/internal-triage-skip` as the first step to enable skip-label support.

## Key conventions

**Commit messages**: Conventional Commits with `--force-scope` enforced. A scope is always required.

**GitHub Actions**: Always pin to a commit SHA, not a tag. Use [pin-github-action](https://github.com/mheap/pin-github-action) CLI for pinning.

**Kubernetes resource creation**: Use the idempotent dry-run pattern everywhere:
```bash
kubectl create secret generic my-secret --from-literal=key=value \
  --namespace camunda --dry-run=client -o yaml | kubectl apply -f -
```

**Version markers**: `TODO [release-duty]` comments mark locations that need updating at release time (Helm chart versions, image tags, etc.).

**Terraform docs**: Auto-generated from code by `terraform_docs` pre-commit hook into `README.md`. Do not edit the generated sections manually.

**TFLint rules** (`.lint/tflint/.tflint.hcl`): Resource names must match `^[a-z][a-z0-9_]{0,62}[a-z0-9]$`; module names `^[a-z][a-z0-9_]{0,70}[a-z0-9]$`.

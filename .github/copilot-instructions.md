# Copilot Instructions for Camunda Deployment References

## Repository Summary

This repository contains reference architectures for deploying Camunda 8 self-managed using Terraform, scripts, and GitHub Actions for testing. The architectures serve as blueprints for quick learning and rapid deployment across AWS, Azure, and generic cloud environments. Current Camunda version: **8.7**.

**Purpose**: Demonstration and learning (NOT production-ready). Contains deliberate Trivy security warnings that are ignored via `.lint/trivy/.trivyignore`.

## Repository Structure

- **Size**: ~50MB, primarily Terraform configurations and Go tests
- **Languages**: HCL (Terraform), Go (tests), Shell scripts, YAML (workflows)
- **Target Runtime**: Terraform 1.12.2, Go 1.25.0 (see `.tool-versions`)

### Directory Layout
```
├── aws/                          # AWS-specific implementations
│   ├── modules/                  # Reusable AWS modules (eks-cluster, aurora, opensearch, etc.)
│   ├── kubernetes/               # EKS solutions (eks-single-region, eks-single-region-irsa)
│   ├── compute/                  # EC2 solutions (ec2-single-region)
│   └── openshift/               # OpenShift on AWS (rosa-hcp variants)
├── azure/                       # Azure-specific implementations
├── generic/                     # Cloud-agnostic implementations
├── .github/workflows/           # CI/CD pipeline definitions
├── .lint/                       # Linting configurations (tflint, trivy, yamllint)
└── justfile                     # Build recipes and commands
```

**Naming Convention**: `{cloud_provider}/{category}/{solution}-{feature}-{declination}`

## Build & Validation Process

### Prerequisites & Setup
**ALWAYS run this first:**
```bash
# Install all required tools (asdf-managed versions)
just install-tooling

# List all available commands
just --list
```

### Core Commands (in order)
1. **Install dependencies**: `just install-tooling` (installs asdf plugins and tools from `.tool-versions`)
2. **Install Go test dependencies**: `just aws-tf-modules-install-tests-go-mod`
3. **Run Terraform tests**: `just aws-tf-modules-tests` (uses gotestsum, ~120min timeout)
4. **Run single test**: `just aws-tf-modules-test TestName`

### Validation Pipeline
**Pre-commit hooks** (configured in `.pre-commit-config.yaml`):
- `terraform fmt` - Format Terraform files
- `terraform_tflint` - Lint with config at `.lint/tflint/.tflint.hcl`
- `trivy-scan` - Security scan (script: `.lint/trivy/trivy-scan.sh`)
- `shellcheck` - Shell script validation
- `yamllint` - YAML validation (config: `.lint/yamllint/.yamllint.yaml`)
- `actionlint` - GitHub Actions validation

**Manual validation**:
```bash
# Lint Terraform (run from any module directory)
terraform fmt -check -recursive
tflint --config=__GIT_WORKING_DIR__/.lint/tflint/.tflint.hcl

# Security scan
.lint/trivy/trivy-scan.sh

# Run pre-commit hooks manually
pre-commit run --all-files
```

### Time Requirements
- **Tool installation**: 5-10 minutes
- **Go module download**: 1-2 minutes  
- **Full test suite**: Up to 120 minutes (AWS resource provisioning)
- **Single test**: 10-30 minutes
- **Linting**: 1-2 minutes

## Project Architecture

### Key Configuration Files
- `.tool-versions` - Tool version specifications (managed by asdf)
- `.target-branch` - Current target branch for PRs (contains "main")
- `.camunda-version` - Current Camunda version (8.7)
- `justfile` - Build commands and recipes
- `.pre-commit-config.yaml` - Validation hooks configuration

### AWS Modules (Primary Focus)
Located in `aws/modules/`:
- **eks-cluster** - EKS cluster with IRSA, networking, security groups
- **aurora** - PostgreSQL Aurora serverless for Camunda persistence  
- **opensearch** - OpenSearch domain for Zeebe data
- **rosa-hcp** - Red Hat OpenShift on AWS
- **vpn** - VPN gateway configuration

Each module includes: `README.md`, `*.tf` files, `versions.tf` (provider requirements)

### Testing Infrastructure
- **Location**: `aws/modules/.test/src/`
- **Framework**: Terratest with Go 1.25.0
- **Test files**: `*_test.go` (custom_eks_opensearch_test.go, etc.)
- **Environment variables**: `TESTS_CLUSTER_ID`, `CLEAN_CLUSTER_AT_THE_END`, `TF_STATE_BUCKET`

### GitHub Workflows
**Workflow naming**: `{scope}_{cloud}_{category}_{solution}_{action}.yml`
- Testing workflows: `aws_kubernetes_eks_single_region_tests.yml`
- Daily cleanup: `*_daily_cleanup.yml`
- Golden file generation: `*_golden.yml`

**Skip mechanisms**: Add labels like `skip_aws_compute_ec2_single_region_tests` to skip specific workflows.

### Validation Rules
- **TfLint**: Naming convention `^[a-z][a-z0-9_]{0,62}[a-z0-9]$` for resources
- **Trivy**: Security scanning with ignored rules in `.lint/trivy/.trivyignore`
- **Terraform versions**: >= 1.0 (modules), >= 1.6.0 (eks-cluster), >= 1.7.0 (compute)

## Development Workflow

### Making Changes
1. **Branch targeting**: Always target `main` branch (check `.target-branch`)
2. **Documentation preservation**: Preserve existing README.md structure unless specifically told to modify it or when fixing inconsistencies
3. **LICENSE protection**: Never modify the LICENSE file under any circumstances
4. **Run tests locally**: Use `just aws-tf-modules-test TestName` for specific changes
5. **Pre-commit validation**: Hooks run automatically or `pre-commit run --all-files`
6. **CI validation**: Full test suite runs on PR (can be skipped with labels)

### Common Patterns
- **Module structure**: Always include `versions.tf`, `variables.tf`, `outputs.tf`, `README.md`
- **Provider versions**: AWS provider `~> 6.0` consistently used
- **Golden files**: Regenerate with `just regenerate-golden-file` recipe for modules
- **Environment setup**: Check `aws/kubernetes/eks-single-region-irsa/procedure/check-env-variables.sh` for required vars

### Release Process
- **Version updates**: Update `.camunda-version` and workflow scheduler configs
- **Branch strategy**: `main` = next version, `stable/8.x` = released versions
- **Documentation**: Always run `terraform_docs` hook to update module READMEs

## Root Files Reference
Key files in repository root:
- `README.md` - Project overview and getting started
- `DEVELOPER.md` - Workflow conventions and skip label usage  
- `MAINTENANCE.md` - Branching strategy and release process
- `justfile` - Build recipes (153 lines of build automation)
- `.gitignore` - Excludes .terraform/, *.tfstate, build artifacts
- `actionlint` - Local actionlint binary (7MB)

**Trust these instructions** and only search/explore if information is incomplete or incorrect. All common development tasks are covered by the `just` recipes and validation is automated through pre-commit hooks.
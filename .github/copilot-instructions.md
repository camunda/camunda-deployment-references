# Copilot Instructions for Camunda Deployment References

## Repository Overview

This repository contains reference architectures for deploying **Camunda 8 self-managed** using Terraform and GitHub Actions. Current version: **8.7** (see `.camunda-version`).

**Purpose**: Demonstration and learning blueprints for quick deployment across AWS, Azure, and generic cloud environments.

⚠️ **Not production-ready** - Contains deliberate Trivy security warnings (see `.lint/trivy/.trivyignore`).

## Reference Architecture Strategy

As a developer building reference architectures, understand that:

1. **Reference architectures are blueprints** - Users either copy as-is or use as guidance for their own infrastructure
2. **Each architecture maps to workflows** - Every reference architecture has corresponding GitHub Action workflows for integration testing
3. **Documentation lives elsewhere** - Detailed instructions and snippets are in [camunda/camunda-docs](https://github.com/camunda/camunda-docs)
4. **Integration tests are primary** - Focus on end-to-end validation via workflows, not just unit tests

## Essential Files to Reference

Before making changes, always consult these key files:

- **`README.md`** - Repository overview and structure (preserve structure unless fixing inconsistencies)
- **`DEVELOPER.md`** - Workflow naming conventions and skip label usage
- **`MAINTENANCE.md`** - Branching strategy and release process
- **`justfile`** - Build recipes and commands (primarily for module testing)
- **`.target-branch`** - Current target branch for PRs (typically "main")

## Repository Architecture

### Structure Pattern
```
{cloud_provider}/{category}/{solution}-{feature}-{declination}
```

Examples:
- `aws/kubernetes/eks-single-region`
- `aws/openshift/rosa-hcp-dual-region`  
- `azure/kubernetes/aks-single-region`

### Workflow Mapping
Each reference architecture maps to specific GitHub workflows:

| Reference Architecture | Workflow Files |
|------------------------|----------------|
| `aws/kubernetes/eks-single-region` | `aws_kubernetes_eks_single_region_tests.yml` |
| `aws/openshift/rosa-hcp-single-region` | `aws_openshift_rosa_hcp_single_region_tests.yml` |
| `azure/kubernetes/aks-single-region` | `azure_kubernetes_aks_single_region_tests.yml` |

**Pattern**: `{cloud}_{category}_{solution}_{feature}_{action}.yml`

## Development Workflow

### Prerequisites
```bash
# Install all tools (asdf-managed versions from .tool-versions)
just install-tooling

# List available commands
just --list
```

### Module-Level Testing (via justfile)
- `just aws-tf-modules-test TestName` - Run specific Terratest
- `just aws-tf-modules-tests` - Run all module tests (~120min)
- `just regenerate-golden-file` - Update golden files for modules

### Integration Testing (via GitHub Workflows)
- Integration tests run automatically via workflows mapped to each reference architecture
- Use skip labels (see `DEVELOPER.md`) to avoid unnecessary resource provisioning
- Workflows contain the complete integration logic for each architecture

### File Protection Rules
- **LICENSE**: Never modify under any circumstances
- **README.md**: Preserve structure unless specifically told to modify or fixing inconsistencies
- **Configuration files**: Only update versions in `.camunda-version`, `.tool-versions` as needed

### Branching and Targeting
- Target branch: Check `.target-branch` file (typically "main")
- Branching strategy: See `MAINTENANCE.md` for details on stable branches vs main

## Validation Pipeline

Pre-commit hooks handle validation automatically:
- Terraform formatting and linting
- Security scanning (Trivy)
- Shell script validation
- YAML validation
- GitHub Actions validation

Manual validation commands are available in the `justfile` and `.lint/` directory scripts.

## Key Development Guidelines

1. **Focus on integration** - The workflows contain the real testing logic for reference architectures
2. **Reference existing patterns** - Follow established naming conventions from `DEVELOPER.md`
3. **Respect file boundaries** - Don't modify protected files (LICENSE, core documentation structure)
4. **Use workflow skip labels** - Prevent unnecessary CI runs during development
5. **Document in camunda-docs** - Complex documentation and snippets belong in the documentation repository

This repository is optimized for blueprint creation and testing, not production deployment. Always prioritize clarity and educational value in your implementations.
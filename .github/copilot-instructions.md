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

## Documentation Coordination

When making changes to reference architectures:

1. **Request associated documentation PRs** - Always ask for the corresponding documentation changes in the [camunda/camunda-docs](https://github.com/camunda/camunda-docs) repository
2. **Perform side-reviews** - Maintain a copy of the camunda-docs repository to cross-reference and identify:
   - Inconsistencies between code and documentation
   - Required documentation updates
   - Missing or outdated snippets and instructions
3. **Coordinate changes** - Ensure reference architecture modifications align with documentation patterns and examples

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

### Testing Strategy (via GitHub Workflows and terraform apply)
- **Primary testing approach**: Use `.github/workflows` files and `tests` folder exclusively
- **Cloud provider integration**: Workflow files and actions run reference architectures directly in cloud providers via terraform apply
- **Iterative feedback**: Adopt a test strategy that relies on terraform apply and iterate based on GitHub Actions output
- **Resource isolation**: Always use tags to interact only with resources from your current workspace or PR
- **Integration focus**: Workflows contain the complete integration logic for each architecture
- **Debugging tools**: You may use additional tools for debugging in the test environment
- Use skip labels (see `DEVELOPER.md`) to avoid unnecessary resource provisioning during development

## Code Review Guidelines

### Terraform Module Validation
When reviewing terraform modules, perform comprehensive validation:

1. **Version Verification**: Check each module reference with appropriate version constraints
2. **Parameter Documentation**: Ensure every parameter either:
   - Self-documents with clear, descriptive names
   - Has detailed descriptions explaining purpose, expected values, and impact
   - Includes examples for complex configurations
3. **Implementation Reasoning**: Provide explanations for non-obvious implementation choices to support smooth onboarding
4. **Variable Validation**: Add terraform validation blocks where appropriate to prevent misconfiguration
5. **Default Values**: Ensure sensible defaults are provided with justification for the chosen values

### Pull Request Review Process

#### Deprecation Management
- **Highlight deprecations**: When deprecated features, modules, or configurations are found, open a discussion thread
- **Require justification**: The author must provide clear reasoning for using deprecated features
- **Migration path**: Include guidance or timeline for moving away from deprecated components
- **Documentation**: Update associated documentation to reflect deprecation status and alternatives

#### Organization Standards
- **Alphabetical ordering**: When no logical grouping exists (business logic, technical dependencies), maintain alphabetical ordering in:
  - Variable definitions
  - Resource declarations
  - Module references
  - Output definitions
- **Consistent grouping**: When grouping is used, clearly document the grouping criteria and maintain consistency

### File Protection Rules
- **LICENSE**: Never modify under any circumstances
- **README.md**: Preserve structure unless specifically told to modify or fixing inconsistencies
- **Configuration files**: Only update versions in `.camunda-version`, `.tool-versions` as needed

### Security and Confidentiality
- **Never leak confidential information** - Do not expose credentials, sensitive data, or confidential information in any part of the codebase, logs, or outputs
- **Mask sensitive data in CI** - When working with credentials or sensitive information, ensure they are properly masked in GitHub Actions and CI outputs
- **Resource isolation** - Use appropriate workspace or PR-specific tags to prevent accidental interaction with production or other environments

### Branching and Targeting
- Target branch: Check `.target-branch` file (typically "main")
- Branching strategy: See `MAINTENANCE.md` for details on stable branches vs main

## Validation Pipeline

**Always use pre-commit hooks** when performing commits or any interaction with this repository. The pre-commit configuration (`.pre-commit-config.yaml`) provides comprehensive validation:
- Terraform formatting and linting
- Security scanning (Trivy)
- Shell script validation
- YAML validation
- GitHub Actions validation
- Conventional commit message validation
- Go code formatting and validation

The pre-commit hooks help detect formatting, lint, and other errors before commits. Manual validation commands are also available in the `justfile` and `.lint/` directory scripts.

## Key Development Guidelines

1. **Focus on integration** - The workflows contain the real testing logic for reference architectures
2. **Reference existing patterns** - Follow established naming conventions from `DEVELOPER.md`
3. **Respect file boundaries** - Don't modify protected files (LICENSE, core documentation structure)
4. **Use workflow skip labels** - Prevent unnecessary CI runs during development
5. **Document in camunda-docs** - Complex documentation and snippets belong in the documentation repository
6. **Coordinate documentation** - Request associated documentation PRs and perform cross-repository reviews
7. **Test with terraform apply** - Use GitHub workflows that deploy to actual cloud providers for validation
8. **Smooth onboarding focus** - Ensure all implementations include clear reasoning and documentation for new repository joiners
9. **Comprehensive code review** - Validate terraform modules, versions, parameters, and highlight any deprecations
10. **Maintain organization** - Use alphabetical ordering when no logical grouping criteria exists

This repository is optimized for blueprint creation and testing, not production deployment. Always prioritize clarity and educational value in your implementations.
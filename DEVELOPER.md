# Developer Documentation

## Workflow Naming Convention

Our workflows follow a standardized naming convention to ensure clarity and consistency across internal and external processes.

### Internal Workflows
All internal workflows are prefixed with `internal_` followed by:
1. **Scope**: Either `global`, `openshift`, or any related component name.
2. **Workflow Purpose**: A description of the workflow's function.

#### Examples:
- `internal_global_lint.yml`: Linting workflow for global scope.
- `internal_openshift_lint.yml`: Linting workflow for OpenShift scope.
- `internal_openshift_artifact_rosa_versions.yml`: Workflow for managing ROSA artifact versions in OpenShift.

### Test Workflows
For architecture reference tests, the naming follows the folder structure where the tests reside.

#### Example:
For a test located in `aws/openshift/rosa-hcp-single-region`, the corresponding workflow file is named:
```
aws_openshift_rosa_hcp_single_region_tests.yml
```

## Standardized Workflow Naming
Inside each workflow file, the `name` field is also standardized to maintain uniformity.

#### Examples:
- **Linting Workflow:**
  ```yaml
  name: Internal - Global - Lint
  ```
- **Integration Test Workflow:**
  ```yaml
  name: Tests - Integration - AWS OpenShift ROSA HCP Single Region
  ```
- **Daily Cleanup Workflow:**
  ```yaml
  name: Tests - Daily Cleanup - AWS OpenShift ROSA HCP Single Region
  ```

By following these conventions, we ensure a clear and structured approach to workflow management, making it easier to understand, maintain, and scale our CI/CD pipelines.

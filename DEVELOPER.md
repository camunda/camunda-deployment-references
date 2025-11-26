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

## Tooling Installation

The project uses `just` (a command runner) to manage tooling installation. To install all required tools, run:

```bash
just install-tooling
```

This command will:
1. Install all tools defined in `.tool-versions` via `asdf`

## Skipping Workflows Using Labels

The action `.github/actions/internal-triage-skip` allows skipping workflows using specific labels. This action must be included in every workflow to enable this functionality.

### Implementation Example

Each workflow should contain a `triage` job to check for skip labels:

```yaml
triage:
    runs-on: ubuntu-latest
    outputs:
        should_skip: ${{ steps.skip_check.outputs.should_skip }}
    steps:
        - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4
        - name: Check labels
          id: skip_check
          uses: ./.github/actions/internal-triage-skip

clusters-info:
    needs:
        - triage
    if: needs.triage.outputs.should_skip == 'false'
```

### Creating and Using Skip Labels

A label can be added to a pull request or issue to skip a specific workflow execution. For example, adding the label [`skip_aws_compute_ec2_single_region_tests`](https://github.com/camunda/camunda-deployment-references/labels/skip_aws_compute_ec2_single_region_tests) prevents unnecessary resource usage.

If the required label does not exist, it must be created manually on GitHub at [GitHub Labels](https://github.com/camunda/camunda-deployment-references/issues/labels) with the color `#1D76DB`.

_Note:_ One should create and apply the label during the creation of the PR; otherwise, the first run will trigger all workflows.

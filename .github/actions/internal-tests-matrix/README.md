# Generate Tests Matrix

## Description

Generates a test matrix from a CI matrix file, applies filtering based on scheduling, and sets cluster names and scenarios.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster_name` | <p>Optional cluster name to use, otherwise a random one is generated</p> | `false` | `""` |
| `cluster_prefix` | <p>Prefix of the cluster name in case of generated name</p> | `false` | `hci-` |
| `ref_arch` | <p>Scenario name to use for filtering during workflow_dispatch</p> | `false` | `""` |
| `ci_matrix_file` | <p>Path to the CI matrix file</p> | `true` | `""` |
| `is_schedule` | <p>Set to true if the run is scheduled</p> | `true` | `""` |
| `is_renovate_pr` | <p>Set to true if the PR is from Renovate</p> | `true` | `""` |


## Outputs

| name | description |
| --- | --- |
| `platform_matrix` | <p>The final platform matrix in JSON format</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-tests-matrix@main
  with:
    cluster_name:
    # Optional cluster name to use, otherwise a random one is generated
    #
    # Required: false
    # Default: ""

    cluster_prefix:
    # Prefix of the cluster name in case of generated name
    #
    # Required: false
    # Default: hci-

    ref_arch:
    # Scenario name to use for filtering during workflow_dispatch
    #
    # Required: false
    # Default: ""

    ci_matrix_file:
    # Path to the CI matrix file
    #
    # Required: true
    # Default: ""

    is_schedule:
    # Set to true if the run is scheduled
    #
    # Required: true
    # Default: ""

    is_renovate_pr:
    # Set to true if the PR is from Renovate
    #
    # Required: true
    # Default: ""
```

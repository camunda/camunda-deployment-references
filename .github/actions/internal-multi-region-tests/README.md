# Internal Multi-Region Tests

## Description

Run tests across multiple regions

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-0-namespace` | <p>Camunda namespace for Cluster 0</p> | `true` | `camunda-platform` |
| `cluster-1-namespace` | <p>Camunda namespace for Cluster 1</p> | `true` | `camunda-platform` |
| `helm-version` | <p>Helm version to test</p> | `true` | `""` |
| `cluster-name` | <p>Value used for naming some things but not actively used to decide on context</p> | `false` | `dual-region-cluster` |
| `backup-name` | <p>Name of the backup that should be created, important in shared s3 buckets</p> | `false` | `""` |
| `default-values-yaml` | <p>Path to default values yaml file</p> | `false` | `./multi-region-tests/test/values.yaml` |
| `region-0-values-yaml` | <p>Path to region 0 values yaml file</p> | `false` | `./multi-region-tests/test/values-region-0.yaml` |
| `region-1-values-yaml` | <p>Path to region 1 values yaml file</p> | `false` | `./multi-region-tests/test/values-region-1.yaml` |
| `extra-values-yaml` | <p>Comma separated string of extra values yaml files to be applied</p> | `false` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-multi-region-tests@main
  with:
    cluster-0-namespace:
    # Camunda namespace for Cluster 0
    #
    # Required: true
    # Default: camunda-platform

    cluster-1-namespace:
    # Camunda namespace for Cluster 1
    #
    # Required: true
    # Default: camunda-platform

    helm-version:
    # Helm version to test
    #
    # Required: true
    # Default: ""

    cluster-name:
    # Value used for naming some things but not actively used to decide on context
    #
    # Required: false
    # Default: dual-region-cluster

    backup-name:
    # Name of the backup that should be created, important in shared s3 buckets
    #
    # Required: false
    # Default: ""

    default-values-yaml:
    # Path to default values yaml file
    #
    # Required: false
    # Default: ./multi-region-tests/test/values.yaml

    region-0-values-yaml:
    # Path to region 0 values yaml file
    #
    # Required: false
    # Default: ./multi-region-tests/test/values-region-0.yaml

    region-1-values-yaml:
    # Path to region 1 values yaml file
    #
    # Required: false
    # Default: ./multi-region-tests/test/values-region-1.yaml

    extra-values-yaml:
    # Comma separated string of extra values yaml files to be applied
    #
    # Required: false
    # Default: ""
```

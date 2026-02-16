# Cleanup ECK Elasticsearch Deployment

## Description

Removes the Elasticsearch cluster and optionally the ECK operator.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace where Elasticsearch was deployed</p> | `true` | `""` |
| `skip-operator-uninstall` | <p>Skip uninstalling the ECK operator</p> | `false` | `false` |
| `eck-operator-namespace` | <p>Namespace for the ECK operator</p> | `false` | `elastic-system` |


## Outputs

| name | description |
| --- | --- |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-eck-operator-cleanup@main
  with:
    namespace:
    # Kubernetes namespace where Elasticsearch was deployed
    #
    # Required: true
    # Default: ""

    skip-operator-uninstall:
    # Skip uninstalling the ECK operator
    #
    # Required: false
    # Default: false

    eck-operator-namespace:
    # Namespace for the ECK operator
    #
    # Required: false
    # Default: elastic-system
```

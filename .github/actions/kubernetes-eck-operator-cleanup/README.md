# Cleanup ECK Elasticsearch Deployment

## Description

Removes the Elasticsearch cluster and optionally the ECK operator.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace where Elasticsearch was deployed</p> | `false` | `camunda` |
| `skip-operator-uninstall` | <p>Skip uninstalling the ECK operator (CRDs are cluster-wide; default true for safety)</p> | `false` | `true` |


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
    # Required: false
    # Default: camunda

    skip-operator-uninstall:
    # Skip uninstalling the ECK operator (CRDs are cluster-wide; default true for safety)
    #
    # Required: false
    # Default: true
```

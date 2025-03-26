# Camunda Chart Tests

## Description

Run the Camunda Helm chart tests. Already requires the Helm chart to be deployed and cluster access granted.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tests-camunda-helm-chart-repo-ref` | <p>The branch, tag or commit to checkout</p> | `true` | `""` |
| `tests-camunda-helm-chart-repo-path` | <p>Path to the Helm chart repository</p> | `true` | `""` |
| `secrets` | <p>JSON wrapped secrets for easier secret passing</p> | `true` | `""` |
| `camunda-version` | <p>The version of the Camunda Helm chart to test</p> | `true` | `""` |
| `camunda-domain` | <p>The domain to use for the tests</p> | `false` | `false` |
| `webmodeler-enabled` | <p>Whether the Webmodeler is enabled in the chart</p> | `false` | `false` |
| `console-enabled` | <p>Whether the Console is enabled in the chart</p> | `false` | `false` |
| `test-namespace` | <p>The namespace to use for the tests</p> | `false` | `camunda` |
| `test-cluster-type` | <p>The type of the cluster to use for the tests</p> | `false` | `kubernetes` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-camunda-chart-tests@main
  with:
    tests-camunda-helm-chart-repo-ref:
    # The branch, tag or commit to checkout
    #
    # Required: true
    # Default: ""

    tests-camunda-helm-chart-repo-path:
    # Path to the Helm chart repository
    #
    # Required: true
    # Default: ""

    secrets:
    # JSON wrapped secrets for easier secret passing
    #
    # Required: true
    # Default: ""

    camunda-version:
    # The version of the Camunda Helm chart to test
    #
    # Required: true
    # Default: ""

    camunda-domain:
    # The domain to use for the tests
    #
    # Required: false
    # Default: false

    webmodeler-enabled:
    # Whether the Webmodeler is enabled in the chart
    #
    # Required: false
    # Default: false

    console-enabled:
    # Whether the Console is enabled in the chart
    #
    # Required: false
    # Default: false

    test-namespace:
    # The namespace to use for the tests
    #
    # Required: false
    # Default: camunda

    test-cluster-type:
    # The type of the cluster to use for the tests
    #
    # Required: false
    # Default: kubernetes
```

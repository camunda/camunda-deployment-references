# Internal Helm Deprecation Check

## Description

Check for deprecation warnings and errors in the deployed Camunda Helm chart.
Uses `helm get notes` to retrieve the release notes and scans for
`[camunda][warning]` (deprecated configuration) and `[camunda][error]`
(removed configuration) messages.
Optionally validates that deployed values do not contain unknown keys
by checking against a strict version of the chart's JSON Schema.
Fails the pipeline if any deprecation warnings, errors, or unknown keys are found.
See: https://github.com/camunda/camunda-platform-helm/issues/4564


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `release-name` | <p>The Helm release name to check</p> | `false` | `camunda` |
| `namespace` | <p>The Kubernetes namespace where the release is deployed</p> | `false` | `camunda` |
| `kube-context` | <p>The Kubernetes context to use (optional, defaults to current context)</p> | `false` | `""` |
| `exclude-patterns` | <p>Newline-separated list of fixed strings to exclude from warnings and errors. Messages containing any of these strings will be ignored.</p> | `false` | `""` |
| `check-unknown-keys` | <p>When set to 'true', deployed values are validated against a strict version of the chart's JSON Schema to detect unknown keys (typos, removed properties). The schema is automatically extracted from the deployed chart. See: https://github.com/camunda/camunda-platform-helm/issues/4564</p> | `false` | `true` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-helm-deprecation-check@main
  with:
    release-name:
    # The Helm release name to check
    #
    # Required: false
    # Default: camunda

    namespace:
    # The Kubernetes namespace where the release is deployed
    #
    # Required: false
    # Default: camunda

    kube-context:
    # The Kubernetes context to use (optional, defaults to current context)
    #
    # Required: false
    # Default: ""

    exclude-patterns:
    # Newline-separated list of fixed strings to exclude from warnings and errors.
    # Messages containing any of these strings will be ignored.
    #
    # Required: false
    # Default: ""

    check-unknown-keys:
    # When set to 'true', deployed values are validated against a strict
    # version of the chart's JSON Schema to detect unknown keys
    # (typos, removed properties).
    # The schema is automatically extracted from the deployed chart.
    # See: https://github.com/camunda/camunda-platform-helm/issues/4564
    #
    # Required: false
    # Default: true
```

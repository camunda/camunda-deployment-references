# Configure Wildcard Certificate Usage

## Description

Determines whether to use wildcard certificates or Let's Encrypt based on PR context.
For Renovate PRs, automatically detects if cert-manager is modified.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `manual-wildcard-cert` | <p>Manual override to use wildcard certificate (takes precedence)</p> | `false` | `""` |
| `is-renovate-pr` | <p>Whether this is a Renovate bot PR</p> | `true` | `""` |
| `is-schedule` | <p>Whether this is a scheduled run</p> | `true` | `""` |
| `base-ref` | <p>Base branch reference for diff comparison</p> | `false` | `main` |


## Outputs

| name | description |
| --- | --- |
| `use-wildcard-cert` | <p>Whether to use wildcard certificate (true/false)</p> |
| `has-cert-manager-changes` | <p>Whether the PR contains cert-manager changes (only set for Renovate PRs)</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-configure-wildcard-cert@main
  with:
    manual-wildcard-cert:
    # Manual override to use wildcard certificate (takes precedence)
    #
    # Required: false
    # Default: ""

    is-renovate-pr:
    # Whether this is a Renovate bot PR
    #
    # Required: true
    # Default: ""

    is-schedule:
    # Whether this is a scheduled run
    #
    # Required: true
    # Default: ""

    base-ref:
    # Base branch reference for diff comparison
    #
    # Required: false
    # Default: main
```

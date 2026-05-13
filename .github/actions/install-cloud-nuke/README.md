# Install cloud-nuke

## Description

Install the gruntwork-io/cloud-nuke binary at a pinned version onto the runner.
Used by cleanup workflows to delete AWS resources outside of Terraform state.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `version` | <p>cloud-nuke release tag (e.g. v0.49.0)</p> | `false` | `v0.49.0` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/install-cloud-nuke@main
  with:
    version:
    # cloud-nuke release tag (e.g. v0.49.0)
    #
    # Required: false
    # Default: v0.49.0
```

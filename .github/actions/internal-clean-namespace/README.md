# Clean namespace

## Description

Clean a single namespace for a fresh test environment

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>The namespace to clean</p> | `true` | `""` |
| `recreate` | <p>Whether to recreate the namespace after deletion</p> | `false` | `false` |
| `openshift-project` | <p>Use oc new-project for OpenShift with metadata</p> | `false` | `false` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-clean-namespace@main
  with:
    namespace:
    # The namespace to clean
    #
    # Required: true
    # Default: ""

    recreate:
    # Whether to recreate the namespace after deletion
    #
    # Required: false
    # Default: false

    openshift-project:
    # Use oc new-project for OpenShift with metadata
    #
    # Required: false
    # Default: false
```

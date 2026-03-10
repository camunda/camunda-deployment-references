# Internal Helm Registry Login

## Description

Authenticate to registry.camunda.cloud OCI registry for Helm chart pulls.
Only performs login when the chart version matches a dev pattern (e.g. dev-latest).
Retrieves credentials from Vault automatically.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `helm-chart-version` | <p>The Helm chart version being used. Login is only performed for non-standard versions (e.g. dev-latest).</p> | `true` | `""` |
| `vault-addr` | <p>Vault server URL</p> | `true` | `""` |
| `vault-role-id` | <p>Vault AppRole role ID</p> | `true` | `""` |
| `vault-secret-id` | <p>Vault AppRole secret ID</p> | `true` | `""` |
| `registry-host` | <p>The OCI registry host to authenticate against</p> | `false` | `registry.camunda.cloud` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-helm-registry-login@main
  with:
    helm-chart-version:
    # The Helm chart version being used. Login is only performed for non-standard versions (e.g. dev-latest).
    #
    # Required: true
    # Default: ""

    vault-addr:
    # Vault server URL
    #
    # Required: true
    # Default: ""

    vault-role-id:
    # Vault AppRole role ID
    #
    # Required: true
    # Default: ""

    vault-secret-id:
    # Vault AppRole secret ID
    #
    # Required: true
    # Default: ""

    registry-host:
    # The OCI registry host to authenticate against
    #
    # Required: false
    # Default: registry.camunda.cloud
```

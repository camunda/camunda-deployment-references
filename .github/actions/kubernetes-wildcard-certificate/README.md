# Kubernetes Wildcard Certificate Setup

## Description

Setup wildcard TLS certificate from Vault for Kubernetes clusters

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tld` | <p>Top-level domain for the wildcard certificate</p> | `false` | `camunda.ie` |
| `namespace` | <p>Kubernetes namespace where cert-manager resources will be created</p> | `false` | `cert-manager` |
| `vault-addr` | <p>Vault server address</p> | `true` | `""` |
| `vault-role-id` | <p>Vault AppRole role ID</p> | `true` | `""` |
| `vault-secret-id` | <p>Vault AppRole secret ID</p> | `true` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-wildcard-certificate@main
  with:
    tld:
    # Top-level domain for the wildcard certificate
    #
    # Required: false
    # Default: camunda.ie

    namespace:
    # Kubernetes namespace where cert-manager resources will be created
    #
    # Required: false
    # Default: cert-manager

    vault-addr:
    # Vault server address
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
```

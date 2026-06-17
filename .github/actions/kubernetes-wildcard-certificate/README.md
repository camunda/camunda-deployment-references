# Kubernetes Wildcard Certificate Setup

## Description

Setup wildcard TLS certificate from Vault for Kubernetes clusters

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tld` | <p>Top-level domain for the wildcard certificate</p> | `false` | `camunda.ie` |
| `namespace` | <p>Kubernetes namespace where the TLS secret will be created</p> | `false` | `camunda` |
| `secret-name` | <p>Name(s) of the TLS secret(s) to create from the same wildcard certificate. Accepts a single name or a newline-separated list to provision multiple identical TLS secrets (e.g. one for the Camunda ingress and one for a separate component) without burning Let's Encrypt quota.</p> | `false` | `camunda-tls` |
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
    # Kubernetes namespace where the TLS secret will be created
    #
    # Required: false
    # Default: camunda

    secret-name:
    # Name(s) of the TLS secret(s) to create from the same wildcard certificate.
    # Accepts a single name or a newline-separated list to provision multiple
    # identical TLS secrets (e.g. one for the Camunda ingress and one for a
    # separate component) without burning Let's Encrypt quota.
    #
    # Required: false
    # Default: camunda-tls

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

# Configure AWS CLI

## Description

Import AWS Secrets from Vault and configure AWS CLI profile

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `vault-addr` | <p>The URL of the Vault server</p> | `true` | `""` |
| `vault-role-id` | <p>The Vault Role ID</p> | `true` | `""` |
| `vault-secret-id` | <p>The Vault Secret ID</p> | `true` | `""` |
| `aws-profile` | <p>AWS CLI profile name</p> | `true` | `""` |
| `aws-region` | <p>AWS region</p> | `true` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-configure-cli@main
  with:
    vault-addr:
    # The URL of the Vault server
    #
    # Required: true
    # Default: ""

    vault-role-id:
    # The Vault Role ID
    #
    # Required: true
    # Default: ""

    vault-secret-id:
    # The Vault Secret ID
    #
    # Required: true
    # Default: ""

    aws-profile:
    # AWS CLI profile name
    #
    # Required: true
    # Default: ""

    aws-region:
    # AWS region
    #
    # Required: true
    # Default: ""
```

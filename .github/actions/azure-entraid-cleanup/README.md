# Cleanup Azure EntraID

## Description

Destroys temporary Azure AD app registration created for testing

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `azure-credentials` | <p>Azure credentials JSON (required if use-oidc is false)</p> | `false` | `""` |
| `use-oidc` | <p>Use OIDC authentication instead of azure-credentials JSON</p> | `false` | `false` |
| `azure-client-id` | <p>Azure Client ID (required if use-oidc is true)</p> | `false` | `""` |
| `azure-tenant-id` | <p>Azure Tenant ID (required if use-oidc is true)</p> | `false` | `""` |
| `azure-subscription-id` | <p>Azure Subscription ID (required if use-oidc is true)</p> | `false` | `""` |
| `terraform-backend-bucket` | <p>S3 bucket for Terraform state</p> | `true` | `""` |
| `terraform-backend-region` | <p>S3 bucket region</p> | `true` | `""` |
| `terraform-backend-key` | <p>S3 key for Terraform state</p> | `true` | `""` |
| `aws-profile` | <p>AWS profile to use for S3 backend (must be configured beforehand)</p> | `false` | `infex` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/azure-entraid-cleanup@main
  with:
    azure-credentials:
    # Azure credentials JSON (required if use-oidc is false)
    #
    # Required: false
    # Default: ""

    use-oidc:
    # Use OIDC authentication instead of azure-credentials JSON
    #
    # Required: false
    # Default: false

    azure-client-id:
    # Azure Client ID (required if use-oidc is true)
    #
    # Required: false
    # Default: ""

    azure-tenant-id:
    # Azure Tenant ID (required if use-oidc is true)
    #
    # Required: false
    # Default: ""

    azure-subscription-id:
    # Azure Subscription ID (required if use-oidc is true)
    #
    # Required: false
    # Default: ""

    terraform-backend-bucket:
    # S3 bucket for Terraform state
    #
    # Required: true
    # Default: ""

    terraform-backend-region:
    # S3 bucket region
    #
    # Required: true
    # Default: ""

    terraform-backend-key:
    # S3 key for Terraform state
    #
    # Required: true
    # Default: ""

    aws-profile:
    # AWS profile to use for S3 backend (must be configured beforehand)
    #
    # Required: false
    # Default: infex
```

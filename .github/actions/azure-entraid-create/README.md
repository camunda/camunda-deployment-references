# Create Azure EntraID for Testing

## Description

Creates a temporary Azure AD app registration for Camunda OIDC testing

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `resource-prefix` | <p>Prefix for EntraID resources</p> | `true` | `""` |
| `domain-name` | <p>Domain name for Camunda deployment</p> | `true` | `""` |
| `azure-credentials` | <p>Azure credentials JSON (required if use-oidc is false)</p> | `false` | `""` |
| `use-oidc` | <p>Use OIDC authentication instead of azure-credentials JSON</p> | `false` | `false` |
| `azure-client-id` | <p>Azure Client ID (required if use-oidc is true)</p> | `false` | `""` |
| `azure-tenant-id` | <p>Azure Tenant ID (required if use-oidc is true)</p> | `false` | `""` |
| `azure-subscription-id` | <p>Azure Subscription ID (required if use-oidc is true)</p> | `false` | `""` |
| `enable-webmodeler` | <p>Enable Web Modeler component</p> | `false` | `false` |
| `secret-validity-hours` | <p>Client secret validity in hours</p> | `false` | `168` |
| `terraform-backend-bucket` | <p>S3 bucket for Terraform state</p> | `true` | `""` |
| `terraform-backend-region` | <p>S3 bucket region</p> | `true` | `""` |
| `terraform-backend-key` | <p>S3 key for Terraform state</p> | `true` | `""` |
| `aws-profile` | <p>AWS profile to use for S3 backend (must be configured beforehand)</p> | `false` | `infex` |


## Outputs

| name | description |
| --- | --- |
| `tenant-id` | <p>Azure AD Tenant ID</p> |
| `client-id` | <p>Application Client ID</p> |
| `issuer-url` | <p>OIDC Issuer URL</p> |
| `authorization-url` | <p>OIDC Authorization URL</p> |
| `token-url` | <p>OIDC Token URL</p> |
| `jwks-url` | <p>OIDC JWKS URL</p> |
| `userinfo-url` | <p>OIDC UserInfo URL</p> |
| `identity-client-secret` | <p>Identity component client secret</p> |
| `optimize-client-secret` | <p>Optimize component client secret</p> |
| `orchestration-client-secret` | <p>Orchestration component client secret</p> |
| `connectors-client-secret` | <p>Connectors component client secret</p> |
| `webmodeler-api-client-secret` | <p>Web Modeler API client secret</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/azure-entraid-create@main
  with:
    resource-prefix:
    # Prefix for EntraID resources
    #
    # Required: true
    # Default: ""

    domain-name:
    # Domain name for Camunda deployment
    #
    # Required: true
    # Default: ""

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

    enable-webmodeler:
    # Enable Web Modeler component
    #
    # Required: false
    # Default: false

    secret-validity-hours:
    # Client secret validity in hours
    #
    # Required: false
    # Default: 168

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

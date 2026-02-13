# Create AWS Cognito for Testing

## Description

Creates a temporary AWS Cognito User Pool for Camunda OIDC testing

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `resource-prefix` | <p>Prefix for Cognito resources</p> | `true` | `""` |
| `domain-name` | <p>Bare hostname for Camunda deployment (e.g., my-cluster.camunda.example.com). No protocol, no trailing slash. Does not need to exist in DNS.</p> | `true` | `""` |
| `aws-region` | <p>AWS region for Cognito (uses current region if not specified)</p> | `false` | `""` |
| `enable-webmodeler` | <p>Enable Web Modeler component</p> | `false` | `false` |
| `enable-console` | <p>Enable Console component</p> | `false` | `false` |
| `create-test-user` | <p>Create a test user for simulating human login</p> | `false` | `false` |
| `test-user-name` | <p>Email for the test user</p> | `false` | `camunda-test@example.com` |
| `test-user-password` | <p>Password for the test user</p> | `false` | `CamundaTest123!` |
| `auto-cleanup-hours` | <p>Hours after which this Cognito pool should be cleaned up</p> | `false` | `72` |
| `terraform-backend-bucket` | <p>S3 bucket for Terraform state</p> | `true` | `""` |
| `terraform-backend-region` | <p>S3 bucket region</p> | `true` | `""` |
| `terraform-backend-key` | <p>S3 key for Terraform state</p> | `true` | `""` |
| `aws-profile` | <p>AWS profile to use (must be configured beforehand)</p> | `false` | `infraex` |


## Outputs

| name | description |
| --- | --- |
| `user-pool-id` | <p>Cognito User Pool ID</p> |
| `issuer-url` | <p>OIDC Issuer URL</p> |
| `authorization-url` | <p>OIDC Authorization URL</p> |
| `token-url` | <p>OIDC Token URL</p> |
| `jwks-url` | <p>OIDC JWKS URL</p> |
| `userinfo-url` | <p>OIDC UserInfo URL</p> |
| `resource-server-identifier` | <p>Resource Server identifier (used as scope prefix, e.g., 'camunda')</p> |
| `identity-client-id` | <p>Identity component client ID</p> |
| `identity-client-secret` | <p>Identity component client secret</p> |
| `optimize-client-id` | <p>Optimize component client ID</p> |
| `optimize-client-secret` | <p>Optimize component client secret</p> |
| `orchestration-client-id` | <p>Orchestration component client ID</p> |
| `orchestration-client-secret` | <p>Orchestration component client secret</p> |
| `connectors-client-id` | <p>Connectors component client ID</p> |
| `connectors-client-secret` | <p>Connectors component client secret</p> |
| `console-client-id` | <p>Console component client ID</p> |
| `webmodeler-ui-client-id` | <p>WebModeler UI client ID</p> |
| `webmodeler-api-client-id` | <p>WebModeler API client ID</p> |
| `webmodeler-api-client-secret` | <p>WebModeler API client secret</p> |
| `test-user-name` | <p>Test user email</p> |
| `test-user-password` | <p>Test user password</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-cognito-create@main
  with:
    resource-prefix:
    # Prefix for Cognito resources
    #
    # Required: true
    # Default: ""

    domain-name:
    # Bare hostname for Camunda deployment (e.g., my-cluster.camunda.example.com). No protocol, no trailing slash. Does not need to exist in DNS.
    #
    # Required: true
    # Default: ""

    aws-region:
    # AWS region for Cognito (uses current region if not specified)
    #
    # Required: false
    # Default: ""

    enable-webmodeler:
    # Enable Web Modeler component
    #
    # Required: false
    # Default: false

    enable-console:
    # Enable Console component
    #
    # Required: false
    # Default: false

    create-test-user:
    # Create a test user for simulating human login
    #
    # Required: false
    # Default: false

    test-user-name:
    # Email for the test user
    #
    # Required: false
    # Default: camunda-test@example.com

    test-user-password:
    # Password for the test user
    #
    # Required: false
    # Default: CamundaTest123!

    auto-cleanup-hours:
    # Hours after which this Cognito pool should be cleaned up
    #
    # Required: false
    # Default: 72

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
    # AWS profile to use (must be configured beforehand)
    #
    # Required: false
    # Default: infraex
```

# Cleanup AWS Cognito

## Description

Destroys temporary AWS Cognito User Pool created for testing

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `terraform-backend-bucket` | <p>S3 bucket for Terraform state</p> | `true` | `""` |
| `terraform-backend-region` | <p>S3 bucket region</p> | `true` | `""` |
| `terraform-backend-key` | <p>S3 key for Terraform state</p> | `true` | `""` |
| `aws-profile` | <p>AWS profile to use (must be configured beforehand)</p> | `false` | `infraex` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-cognito-cleanup@main
  with:
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

# Utility Actions

## Description

A set of utility steps to be used across different workflows, including:
- Installing Terraform
- Installing AWS CLI
- Setting Terraform variables
- Checking/Creating an S3 bucket


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `awscli-version` | <p>Version of the AWS CLI to install</p> | `false` | `2.15.52` |
| `terraform-version` | <p>Version of Terraform to install</p> | `false` | `latest` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `aws-region` | <p>AWS region to use for S3 bucket operations</p> | `true` | `""` |
| `tf-state-key` | <p>Key use to store the tfstate file (e.g.: /tfstates/terraform.tfstate)</p> | `true` | `""` |
| `tf-cli-config-credentials-hostname` | <p>The hostname of a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file</p> | `false` | `app.terraform.io` |
| `tf-cli-config-credentials-token` | <p>The API token for a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file</p> | `false` | `""` |
| `tf-terraform-wrapper` | <p>Whether or not to install a wrapper for Terraform CLI</p> | `false` | `true` |


## Outputs

| name | description |
| --- | --- |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |
| `TFSTATE_BUCKET` | <p>S3 bucket name for Terraform state</p> |
| `TFSTATE_REGION` | <p>Region of the S3 bucket for Terraform state</p> |
| `TFSTATE_KEY` | <p>Key of the Terraform state file in the S3 bucket</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-tf-eks-module/.github/actions/utility-action@main
  with:
    awscli-version:
    # Version of the AWS CLI to install
    #
    # Required: false
    # Default: 2.15.52

    terraform-version:
    # Version of Terraform to install
    #
    # Required: false
    # Default: latest

    s3-backend-bucket:
    # Name of the S3 bucket to store Terraform state
    #
    # Required: true
    # Default: ""

    s3-bucket-region:
    # Region of the bucket containing the resources states, if not set, will fallback on aws-region
    #
    # Required: false
    # Default: ""

    aws-region:
    # AWS region to use for S3 bucket operations
    #
    # Required: true
    # Default: ""

    tf-state-key:
    # Key use to store the tfstate file (e.g.: /tfstates/terraform.tfstate)
    #
    # Required: true
    # Default: ""

    tf-cli-config-credentials-hostname:
    # The hostname of a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file
    #
    # Required: false
    # Default: app.terraform.io

    tf-cli-config-credentials-token:
    # The API token for a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file
    #
    # Required: false
    # Default: ""

    tf-terraform-wrapper:
    # Whether or not to install a wrapper for Terraform CLI
    #
    # Required: false
    # Default: true
```

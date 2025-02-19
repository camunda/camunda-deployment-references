# Deploy OpenSearch Domain

## Description

This GitHub Action automates the deployment of an OpenSearch domain using Terraform.
It will also install Terraform and awscli. It will output the OpenSearch domain endpoint.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `aws-region` | <p>AWS region where the cluster will be deployed</p> | `true` | `""` |
| `domain-name` | <p>Name of the OpenSearch domain to deploy</p> | `true` | `""` |
| `engine-version` | <p>Version of the OpenSearch engine to deploy</p> | `false` | `2.15` |
| `vpc-id` | <p>VPC ID to create the domain in</p> | `true` | `""` |
| `subnet-ids` | <p>List of subnet IDs to create the domain in</p> | `true` | `""` |
| `cidr-blocks` | <p>CIDR blocks to allow access from and to</p> | `true` | `""` |
| `instance-type` | <p>Instance type for the OpenSearch cluster</p> | `false` | `t3.small.search` |
| `instance-count` | <p>Number of instances in the cluster</p> | `false` | `3` |
| `additional-terraform-vars` | <p>JSON object containing additional Terraform variables</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `false` | `main` |
| `tf-modules-path` | <p>Path where the tf OpenSearch modules will be cloned</p> | `false` | `./.action-tf-modules/opensearch/` |
| `tf-cli-config-credentials-hostname` | <p>The hostname of a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file. Defaults to <code>app.terraform.io</code>.</p> | `false` | `app.terraform.io` |
| `tf-cli-config-credentials-token` | <p>The API token for a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file.</p> | `false` | `""` |
| `tf-terraform-version` | <p>The version of Terraform CLI to install. Defaults to <code>latest</code>.</p> | `false` | `latest` |
| `tf-terraform-wrapper` | <p>Whether or not to install a wrapper to wrap subsequent calls of the <code>terraform</code> binary and expose its STDOUT, STDERR, and exit code as outputs named <code>stdout</code>, <code>stderr</code>, and <code>exitcode</code> respectively. Defaults to <code>true</code>.</p> | `false` | `true` |
| `awscli-version` | <p>Version of the aws cli to use</p> | `false` | `2.15.52` |


## Outputs

| name | description |
| --- | --- |
| `opensearch-endpoint` | <p>The endpoint of the deployed OpenSearch domain</p> |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |
| `all-terraform-outputs` | <p>All outputs from Terraform</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-tf-eks-module/.github/actions/opensearch-manage-cluster@main
  with:
    aws-region:
    # AWS region where the cluster will be deployed
    #
    # Required: true
    # Default: ""

    domain-name:
    # Name of the OpenSearch domain to deploy
    #
    # Required: true
    # Default: ""

    engine-version:
    # Version of the OpenSearch engine to deploy
    #
    # Required: false
    # Default: 2.15

    vpc-id:
    # VPC ID to create the domain in
    #
    # Required: true
    # Default: ""

    subnet-ids:
    # List of subnet IDs to create the domain in
    #
    # Required: true
    # Default: ""

    cidr-blocks:
    # CIDR blocks to allow access from and to
    #
    # Required: true
    # Default: ""

    instance-type:
    # Instance type for the OpenSearch cluster
    #
    # Required: false
    # Default: t3.small.search

    instance-count:
    # Number of instances in the cluster
    #
    # Required: false
    # Default: 3

    additional-terraform-vars:
    # JSON object containing additional Terraform variables
    #
    # Required: false
    # Default: {}

    s3-backend-bucket:
    # Name of the S3 bucket to store Terraform state
    #
    # Required: true
    # Default: ""

    s3-bucket-region:
    # Region of the bucket containing the resources states
    #
    # Required: false
    # Default: ""

    tf-modules-revision:
    # Git revision of the tf modules to use
    #
    # Required: false
    # Default: main

    tf-modules-path:
    # Path where the tf OpenSearch modules will be cloned
    #
    # Required: false
    # Default: ./.action-tf-modules/opensearch/

    tf-cli-config-credentials-hostname:
    # The hostname of a HCP Terraform/Terraform Enterprise instance to place within the credentials block
    # of the Terraform CLI configuration file. Defaults to `app.terraform.io`.
    #
    # Required: false
    # Default: app.terraform.io

    tf-cli-config-credentials-token:
    # The API token for a HCP Terraform/Terraform Enterprise instance to place
    # within the credentials block of the Terraform CLI configuration file.
    #
    # Required: false
    # Default: ""

    tf-terraform-version:
    # The version of Terraform CLI to install. Defaults to `latest`.
    #
    # Required: false
    # Default: latest

    tf-terraform-wrapper:
    # Whether or not to install a wrapper to wrap subsequent calls of the `terraform` binary
    # and expose its STDOUT, STDERR, and exit code
    # as outputs named `stdout`, `stderr`, and `exitcode` respectively. Defaults to `true`.
    #
    # Required: false
    # Default: true

    awscli-version:
    # Version of the aws cli to use
    #
    # Required: false
    # Default: 2.15.52
```

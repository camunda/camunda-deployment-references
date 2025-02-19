# Deploy RDS Aurora Cluster

## Description

This GitHub Action automates the deployment of an RDS Aurora cluster using Terraform.
This action will also install Terraform and awscli. It will output the Aurora cluster endpoint.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `aws-region` | <p>AWS region where the cluster will be deployed</p> | `true` | `""` |
| `cluster-name` | <p>Name of the RDS Aurora cluster to deploy</p> | `true` | `""` |
| `username` | <p>Username for the PostgreSQL admin user</p> | `true` | `""` |
| `password` | <p>Password for the PostgreSQL admin user</p> | `true` | `""` |
| `vpc-id` | <p>VPC ID to create the cluster in</p> | `true` | `""` |
| `subnet-ids` | <p>List of subnet IDs to create the cluster in</p> | `true` | `""` |
| `cidr-blocks` | <p>CIDR blocks to allow access from and to</p> | `true` | `""` |
| `availability-zones` | <p>Array of availability zones to use for the Aurora cluster</p> | `true` | `""` |
| `additional-terraform-vars` | <p>JSON object containing additional Terraform variables</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `false` | `main` |
| `tf-modules-path` | <p>Path where the tf Aurora modules will be cloned</p> | `false` | `./.action-tf-modules/aurora/` |
| `tf-cli-config-credentials-hostname` | <p>The hostname of a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file. Defaults to <code>app.terraform.io</code>.</p> | `false` | `app.terraform.io` |
| `tf-cli-config-credentials-token` | <p>The API token for a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file.</p> | `false` | `""` |
| `tf-terraform-version` | <p>The version of Terraform CLI to install. Defaults to <code>latest</code>.</p> | `false` | `latest` |
| `tf-terraform-wrapper` | <p>Whether or not to install a wrapper to wrap subsequent calls of the <code>terraform</code> binary and expose its STDOUT, STDERR, and exit code as outputs named <code>stdout</code>, <code>stderr</code>, and <code>exitcode</code> respectively. Defaults to <code>true</code>.</p> | `false` | `true` |
| `awscli-version` | <p>Version of the aws cli to use</p> | `false` | `2.15.52` |


## Outputs

| name | description |
| --- | --- |
| `aurora-endpoint` | <p>The endpoint of the deployed Aurora cluster</p> |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |
| `all-terraform-outputs` | <p>All outputs from Terraform</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-tf-eks-module/.github/actions/aurora-manage-cluster@main
  with:
    aws-region:
    # AWS region where the cluster will be deployed
    #
    # Required: true
    # Default: ""

    cluster-name:
    # Name of the RDS Aurora cluster to deploy
    #
    # Required: true
    # Default: ""

    username:
    # Username for the PostgreSQL admin user
    #
    # Required: true
    # Default: ""

    password:
    # Password for the PostgreSQL admin user
    #
    # Required: true
    # Default: ""

    vpc-id:
    # VPC ID to create the cluster in
    #
    # Required: true
    # Default: ""

    subnet-ids:
    # List of subnet IDs to create the cluster in
    #
    # Required: true
    # Default: ""

    cidr-blocks:
    # CIDR blocks to allow access from and to
    #
    # Required: true
    # Default: ""

    availability-zones:
    # Array of availability zones to use for the Aurora cluster
    #
    # Required: true
    # Default: ""

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
    # Path where the tf Aurora modules will be cloned
    #
    # Required: false
    # Default: ./.action-tf-modules/aurora/

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

# Deploy an EKS Cluster

## Description

This GitHub Action automates the deployment of an EKS (Amazon Elastic Kubernetes Service) cluster using Terraform.
This action will also install Terraform, awscli, and kubectl. The kube context will be set on the created cluster.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `aws-region` | <p>AWS region where the EKS cluster will be deployed</p> | `true` | `""` |
| `cluster-name` | <p>Name of the EKS cluster to deploy</p> | `true` | `""` |
| `additional-terraform-vars` | <p>JSON object containing additional Terraform variables</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `false` | `main` |
| `tf-modules-path` | <p>Path where the tf EKS modules will be cloned</p> | `false` | `./.action-tf-modules/eks/` |
| `login` | <p>Authenticate the current kube context on the created cluster</p> | `false` | `true` |
| `tf-cli-config-credentials-hostname` | <p>The hostname of a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file. Defaults to <code>app.terraform.io</code>.</p> | `false` | `app.terraform.io` |
| `tf-cli-config-credentials-token` | <p>The API token for a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file.</p> | `false` | `""` |
| `tf-terraform-version` | <p>The version of Terraform CLI to install. Instead of full version string you can also specify constraint string starting with "&lt;" (for example <code>&lt;1.13.0</code>) to install the latest version satisfying the constraint. A value of <code>latest</code> will install the latest version of Terraform CLI. Defaults to <code>latest</code>.</p> | `false` | `latest` |
| `tf-terraform-wrapper` | <p>Whether or not to install a wrapper to wrap subsequent calls of the <code>terraform</code> binary and expose its STDOUT, STDERR, and exit code as outputs named <code>stdout</code>, <code>stderr</code>, and <code>exitcode</code> respectively. Defaults to <code>true</code>.</p> | `false` | `true` |
| `awscli-version` | <p>Version of the aws cli to use</p> | `false` | `2.15.52` |


## Outputs

| name | description |
| --- | --- |
| `eks-cluster-endpoint` | <p>The API endpoint of the deployed EKS cluster</p> |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |
| `all-terraform-outputs` | <p>All outputs from Terraform</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-tf-eks-module/.github/actions/eks-manage-cluster@main
  with:
    aws-region:
    # AWS region where the EKS cluster will be deployed
    #
    # Required: true
    # Default: ""

    cluster-name:
    # Name of the EKS cluster to deploy
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
    # Region of the bucket containing the resources states, if not set, will fallback on aws-region
    #
    # Required: false
    # Default: ""

    tf-modules-revision:
    # Git revision of the tf modules to use
    #
    # Required: false
    # Default: main

    tf-modules-path:
    # Path where the tf EKS modules will be cloned
    #
    # Required: false
    # Default: ./.action-tf-modules/eks/

    login:
    # Authenticate the current kube context on the created cluster
    #
    # Required: false
    # Default: true

    tf-cli-config-credentials-hostname:
    # The hostname of a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file. Defaults to `app.terraform.io`.
    #
    # Required: false
    # Default: app.terraform.io

    tf-cli-config-credentials-token:
    # The API token for a HCP Terraform/Terraform Enterprise instance to place within the credentials block of the Terraform CLI configuration file.
    #
    # Required: false
    # Default: ""

    tf-terraform-version:
    # The version of Terraform CLI to install. Instead of full version string you can also specify constraint string starting with "<" (for example `<1.13.0`) to install the latest version satisfying the constraint. A value of `latest` will install the latest version of Terraform CLI. Defaults to `latest`.
    #
    # Required: false
    # Default: latest

    tf-terraform-wrapper:
    # Whether or not to install a wrapper to wrap subsequent calls of the `terraform` binary and expose its STDOUT, STDERR, and exit code as outputs named `stdout`, `stderr`, and `exitcode` respectively. Defaults to `true`.
    #
    # Required: false
    # Default: true

    awscli-version:
    # Version of the aws cli to use
    #
    # Required: false
    # Default: 2.15.52
```

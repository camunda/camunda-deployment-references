# Deploy Azure Kubernetes AKS Single Region Cluster

## Description

This GitHub Action automates the deployment of the azure/kubernetes/aks-single-region reference architecture cluster using Terraform.
The kube context will be set on the created cluster.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `resource-prefix` | <p>Prefix for the resources to be created</p> | `true` | `camunda` |
| `resource-group-name` | <p>Name of the resource group</p> | `true` | `""` |
| `cluster-name` | <p>Name of the AKS cluster to deploy</p> | `true` | `camunda-aks-cluster` |
| `kubernetes-version` | <p>Version of Kubernetes to install</p> | `false` | `1.32` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `true` | `main` |
| `tf-modules-path` | <p>Path where the tf eks modules will be cloned</p> | `true` | `./.action-tf-modules/azure-kubernetes-aks-single-region-create/` |
| `tfvars` | <p>Path to the terraform.tfvars file with the variables for the AKS cluster</p> | `true` | `""` |
| `login` | <p>Authenticate the current kube context on the created cluster</p> | `true` | `true` |
| `ref-arch` | <p>Reference architecture to deploy</p> | `false` | `aks-single-region` |
| `location` | <p>Azure region where the AKS cluster will be deployed</p> | `true` | `""` |
| `tags` | <p>Tags to apply to the cluster and related resources, in JSON format</p> | `false` | `{}` |


## Outputs

| name | description |
| --- | --- |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/azure-kubernetes-aks-single-region-create@main
  with:
    resource-prefix:
    # Prefix for the resources to be created
    #
    # Required: true
    # Default: camunda

    resource-group-name:
    # Name of the resource group
    #
    # Required: true
    # Default: ""

    cluster-name:
    # Name of the AKS cluster to deploy
    #
    # Required: true
    # Default: camunda-aks-cluster

    kubernetes-version:
    # Version of Kubernetes to install
    #
    # Required: false
    # Default: 1.32

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

    s3-bucket-key-prefix:
    # Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.
    #
    # Required: false
    # Default: ""

    tf-modules-revision:
    # Git revision of the tf modules to use
    #
    # Required: true
    # Default: main

    tf-modules-path:
    # Path where the tf eks modules will be cloned
    #
    # Required: true
    # Default: ./.action-tf-modules/azure-kubernetes-aks-single-region-create/

    tfvars:
    # Path to the terraform.tfvars file with the variables for the AKS cluster
    #
    # Required: true
    # Default: ""

    login:
    # Authenticate the current kube context on the created cluster
    #
    # Required: true
    # Default: true

    ref-arch:
    # Reference architecture to deploy
    #
    # Required: false
    # Default: aks-single-region

    location:
    # Azure region where the AKS cluster will be deployed
    #
    # Required: true
    # Default: ""

    tags:
    # Tags to apply to the cluster and related resources, in JSON format
    #
    # Required: false
    # Default: {}
```

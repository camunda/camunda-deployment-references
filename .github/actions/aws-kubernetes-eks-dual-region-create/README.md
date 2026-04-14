# Deploy AWS Kubernetes EKS Dual Region Cluster

## Description

This GitHub Action automates the deployment of the aws/kubernetes/eks-dual-region reference architecture cluster using Terraform.
It creates two EKS clusters in different regions (eu-west-2/London and eu-west-3/Paris) with VPC peering.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>Name of the EKS cluster to deploy (will be suffixed with region names)</p> | `true` | `""` |
| `aws-region` | <p>Primary AWS region (owner region) for the EKS cluster</p> | `false` | `eu-west-2` |
| `kubernetes-version` | <p>Version of Kubernetes to install</p> | `false` | `1.35` |
| `single-nat-gateway` | <p>Whether to use a single NAT gateway or not. Default is true for our tests to save on IPs.</p> | `false` | `true` |
| `tags` | <p>Tags to apply to the cluster and related resources, in JSON format</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `ref-arch` | <p>Reference architecture to deploy</p> | `false` | `eks-dual-region` |


## Outputs

| name | description |
| --- | --- |
| `terraform-state-url-cluster` | <p>URL of the Terraform state file in the S3 bucket</p> |
| `s3-aws-access-key` | <p>AWS access key for the S3 bucket used by Elasticsearch backup</p> |
| `s3-aws-secret-access-key` | <p>AWS secret access key for the S3 bucket used by Elasticsearch backup</p> |
| `s3-bucket-name` | <p>Name of the S3 bucket for Elasticsearch backup</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-kubernetes-eks-dual-region-create@main
  with:
    cluster-name:
    # Name of the EKS cluster to deploy (will be suffixed with region names)
    #
    # Required: true
    # Default: ""

    aws-region:
    # Primary AWS region (owner region) for the EKS cluster
    #
    # Required: false
    # Default: eu-west-2

    kubernetes-version:
    # Version of Kubernetes to install
    #
    # Required: false
    # Default: 1.35

    single-nat-gateway:
    # Whether to use a single NAT gateway or not. Default is true for our tests to save on IPs.
    #
    # Required: false
    # Default: true

    tags:
    # Tags to apply to the cluster and related resources, in JSON format
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

    s3-bucket-key-prefix:
    # Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.
    #
    # Required: false
    # Default: ""

    ref-arch:
    # Reference architecture to deploy
    #
    # Required: false
    # Default: eks-dual-region
```

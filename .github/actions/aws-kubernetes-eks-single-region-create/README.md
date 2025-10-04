# Deploy AWS Kubernetes EKS Single Region Cluster

## Description

This GitHub Action automates the deployment of the aws/kubernetes/eks-single-region(-irsa) reference architecture cluster using Terraform.
The kube context will be set on the created cluster.
Supports conditional deployment of Aurora PostgreSQL and OpenSearch.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>Name of the EKS cluster to deploy</p> | `true` | `""` |
| `aws-region` | <p>AWS region where the EKS cluster will be deployed</p> | `true` | `""` |
| `kubernetes-version` | <p>Version of Kubernetes to install</p> | `false` | `1.32` |
| `single-nat-gateway` | <p>Whether to use a single NAT gateway or not. Default is true for our tests to save on IPs.</p> | `false` | `true` |
| `tags` | <p>Tags to apply to the cluster and related resources, in JSON format</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `true` | `main` |
| `tf-modules-path` | <p>Path where the tf eks modules will be cloned</p> | `true` | `./.action-tf-modules/aws-kubernetes-eks-single-region-create/` |
| `login` | <p>Authenticate the current kube context on the created cluster</p> | `true` | `true` |
| `ref-arch` | <p>Reference architecture to deploy</p> | `false` | `eks-single-region-irsa` |
| `vpn-enabled` | <p>Enable VPN setup module (recommended when private_vpc is true), this will also configure the current runner to use it</p> | `false` | `false` |
| `private-vpc` | <p>The VPC within which the cluster resides will only have private subnets, meaning that it cannot be accessed at all from the public Internet (empty will fallback on default value of the module)</p> | `false` | `""` |
| `deploy-aurora` | <p>Deploy Aurora PostgreSQL database</p> | `false` | `true` |
| `deploy-opensearch` | <p>Deploy OpenSearch domain</p> | `false` | `true` |


## Outputs

| name | description |
| --- | --- |
| `terraform-state-url-cluster` | <p>URL of the Terraform state file in the S3 bucket</p> |
| `terraform-state-url-vpn` | <p>URL of the module "vpn" Terraform state file in the S3 bucket</p> |
| `vpn-client-configs` | <p>Map of VPN client configs</p> |
| `vpn-client-config-file` | <p>Config file used by the VPN</p> |
| `vpn-endpoint` | <p>Endpoint of the VPN to access the created cluster</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-kubernetes-eks-single-region-create@main
  with:
    cluster-name:
    # Name of the EKS cluster to deploy
    #
    # Required: true
    # Default: ""

    aws-region:
    # AWS region where the EKS cluster will be deployed
    #
    # Required: true
    # Default: ""

    kubernetes-version:
    # Version of Kubernetes to install
    #
    # Required: false
    # Default: 1.32

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

    tf-modules-revision:
    # Git revision of the tf modules to use
    #
    # Required: true
    # Default: main

    tf-modules-path:
    # Path where the tf eks modules will be cloned
    #
    # Required: true
    # Default: ./.action-tf-modules/aws-kubernetes-eks-single-region-create/

    login:
    # Authenticate the current kube context on the created cluster
    #
    # Required: true
    # Default: true

    ref-arch:
    # Reference architecture to deploy
    #
    # Required: false
    # Default: eks-single-region-irsa

    vpn-enabled:
    # Enable VPN setup module (recommended when private_vpc is true), this will also configure the current runner to use it
    #
    # Required: false
    # Default: false

    private-vpc:
    # The VPC within which the cluster resides will only have private subnets, meaning that it cannot be accessed at all from the public Internet (empty will fallback on default value of the module)
    #
    # Required: false
    # Default: ""

    deploy-aurora:
    # Deploy Aurora PostgreSQL database
    #
    # Required: false
    # Default: true

    deploy-opensearch:
    # Deploy OpenSearch domain
    #
    # Required: false
    # Default: true
```

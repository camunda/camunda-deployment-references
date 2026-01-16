# Deploy AWS Containers ECS Single Region Fargate

## Description

This GitHub Action automates the deployment of the aws/containers/ecs-single-region-fargate reference architecture using Terraform.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>Name of the ECS cluster to deploy</p> | `true` | `""` |
| `aws-region` | <p>AWS region where the ECS cluster will be deployed</p> | `true` | `""` |
| `tags` | <p>Tags to apply to the cluster and related resources, in JSON format</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the tf modules to use</p> | `true` | `main` |
| `tf-modules-path` | <p>Path where the tf ecs arch will be cloned</p> | `true` | `./.action-tf-modules/aws-containers-ecs-single-region-fargate-create/` |
| `tf-modules-name` | <p>Name of the tf modules to use, the folder to refer to - cluster / vpn</p> | `true` | `cluster` |
| `ref-arch` | <p>Reference architecture to deploy</p> | `false` | `ecs-single-region-fargate` |


## Outputs

| name | description |
| --- | --- |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-containers-ecs-single-region-fargate-create@main
  with:
    cluster-name:
    # Name of the ECS cluster to deploy
    #
    # Required: true
    # Default: ""

    aws-region:
    # AWS region where the ECS cluster will be deployed
    #
    # Required: true
    # Default: ""

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
    # Path where the tf ecs arch will be cloned
    #
    # Required: true
    # Default: ./.action-tf-modules/aws-containers-ecs-single-region-fargate-create/

    tf-modules-name:
    # Name of the tf modules to use, the folder to refer to - cluster / vpn
    #
    # Required: true
    # Default: cluster

    ref-arch:
    # Reference architecture to deploy
    #
    # Required: false
    # Default: ecs-single-region-fargate
```

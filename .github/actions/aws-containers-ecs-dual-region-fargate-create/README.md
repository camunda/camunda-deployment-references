# Deploy AWS Containers ECS Dual Region Fargate

## Description

Deploys the aws/containers/ecs-dual-region-fargate reference architecture.

Internal to this repository. It calls sibling actions by caller-relative
path (./.github/actions/...), which only resolve when this repository is
the one checked out, so the cross-repository usage the generated snippet
below shows will not work as written.

Unlike the single-region architecture, this one is three independent
Terraform states applied in order — vpc/ -> infra/ -> app/ — wired to each
other through terraform_remote_state over S3. The action applies all three
and returns the outputs the procedure scripts and the smoke test need, so
callers never have to re-init the state to read an endpoint.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>Name prefixing every created resource, as <cluster-name>-r0-* and <cluster-name>-r1-*. Keep it short — several AWS resource names cap at 32 characters and the modules add their own suffixes.</p> | `true` | `""` |
| `aws-profile` | <p>AWS CLI profile the Terraform providers should use</p> | `false` | `infraex` |
| `region-0` | <p>Primary region (Aurora Global writer, Zeebe zone priority 1000)</p> | `true` | `""` |
| `region-1` | <p>Secondary region</p> | `true` | `""` |
| `networking-mode` | <p>How the two VPCs are connected — <code>vpc_peering</code> or <code>transit_gateway</code></p> | `false` | `vpc_peering` |
| `secondary-storage-type` | <p>Camunda secondary storage — <code>rdbms</code> (Aurora Global) or <code>opensearch</code></p> | `false` | `rdbms` |
| `single-nat-gateway` | <p>Share one NAT gateway per VPC instead of one per AZ. Cheaper and adequate for a test cluster; not a production shape.</p> | `false` | `true` |
| `tags` | <p>Tags to apply to all resources, in JSON format</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket storing Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the S3 bucket holding the state</p> | `false` | `eu-central-1` |
| `s3-bucket-key-prefix` | <p>Key prefix inside the bucket. Must end with a '/'.</p> | `false` | `""` |
| `tf-modules-revision` | <p>Git revision of the reference architecture to deploy</p> | `false` | `main` |
| `tf-modules-path` | <p>Path the reference architecture is cloned into</p> | `false` | `./.action-tf-modules/aws-containers-ecs-dual-region-fargate-create/` |


## Outputs

| name | description |
| --- | --- |
| `terraform-state-url-prefix` | <p>s3:// prefix under which the three layer states live</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-containers-ecs-dual-region-fargate-create@main
  with:
    cluster-name:
    # Name prefixing every created resource, as <cluster-name>-r0-* and
    # <cluster-name>-r1-*. Keep it short — several AWS resource names cap
    # at 32 characters and the modules add their own suffixes.
    #
    # Required: true
    # Default: ""

    aws-profile:
    # AWS CLI profile the Terraform providers should use
    #
    # Required: false
    # Default: infraex

    region-0:
    # Primary region (Aurora Global writer, Zeebe zone priority 1000)
    #
    # Required: true
    # Default: ""

    region-1:
    # Secondary region
    #
    # Required: true
    # Default: ""

    networking-mode:
    # How the two VPCs are connected — `vpc_peering` or `transit_gateway`
    #
    # Required: false
    # Default: vpc_peering

    secondary-storage-type:
    # Camunda secondary storage — `rdbms` (Aurora Global) or `opensearch`
    #
    # Required: false
    # Default: rdbms

    single-nat-gateway:
    # Share one NAT gateway per VPC instead of one per AZ. Cheaper and
    # adequate for a test cluster; not a production shape.
    #
    # Required: false
    # Default: true

    tags:
    # Tags to apply to all resources, in JSON format
    #
    # Required: false
    # Default: {}

    s3-backend-bucket:
    # Name of the S3 bucket storing Terraform state
    #
    # Required: true
    # Default: ""

    s3-bucket-region:
    # Region of the S3 bucket holding the state
    #
    # Required: false
    # Default: eu-central-1

    s3-bucket-key-prefix:
    # Key prefix inside the bucket. Must end with a '/'.
    #
    # Required: false
    # Default: ""

    tf-modules-revision:
    # Git revision of the reference architecture to deploy
    #
    # Required: false
    # Default: main

    tf-modules-path:
    # Path the reference architecture is cloned into
    #
    # Required: false
    # Default: ./.action-tf-modules/aws-containers-ecs-dual-region-fargate-create/
```

# Deploy AWS Kubernetes EKS Multi Region RDBMS Clusters

## Description

Provisions the aws/kubernetes/eks-multi-region-rdbms reference architecture with Terraform:
N EKS clusters in N regions, a Transit Gateway full mesh between them, the Submariner
firewall rules, and an Aurora Global Database used as RDBMS secondary storage.

Everything lives in a single Terraform state, mirroring aws/kubernetes/eks-single-region
where Aurora sits next to the cluster, so that a single destroy tears the whole
architecture down.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>Base name of the clusters. Each region appends its short name.</p> | `true` | `""` |
| `aws-region` | <p>Region of the first region slot, used for the AWS CLI default.</p> | `false` | `eu-west-2` |
| `active-region-count` | <p>Number of region slots to deploy. Must be the slot count or the slot count minus one; see the reference architecture README for why.</p> | `false` | `3` |
| `kubernetes-version` | <p>Version of Kubernetes to install</p> | `false` | `1.36` |
| `np-desired-node-count` | <p>Desired number of nodes per regional node group</p> | `false` | `3` |
| `single-nat-gateway` | <p>Whether to use a single NAT gateway per region. True in CI to save on IPs.</p> | `false` | `true` |
| `database-instance-class` | <p>Aurora instance class. Kept small in CI.</p> | `false` | `db.r6g.large` |
| `tags` | <p>Tags to apply to every resource, in JSON format</p> | `false` | `{}` |
| `s3-backend-bucket` | <p>Name of the S3 bucket storing the Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the state; falls back on aws-region</p> | `false` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix inside the state bucket. Must end with a '/'.</p> | `false` | `""` |
| `ref-arch` | <p>Reference architecture directory under aws/kubernetes</p> | `false` | `eks-multi-region-rdbms` |


## Outputs

| name | description |
| --- | --- |
| `terraform-state-url` | <p>URL of the Terraform state file in the S3 bucket</p> |
| `region-slot-count` | <p>Number of region slots defined by the topology</p> |
| `active-region-count` | <p>Number of region slots actually deployed</p> |
| `cluster-contexts` | <p>Space-separated kubectl context aliases, one per active region</p> |
| `aws-regions` | <p>Space-separated AWS regions, one per active region slot</p> |
| `submariner-cluster-ids` | <p>Space-separated Submariner cluster IDs, one per active region slot</p> |
| `aurora-global-cluster-id` | <p>Identifier of the Aurora Global Database</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-kubernetes-eks-multi-region-rdbms-create@main
  with:
    cluster-name:
    # Base name of the clusters. Each region appends its short name.
    #
    # Required: true
    # Default: ""

    aws-region:
    # Region of the first region slot, used for the AWS CLI default.
    #
    # Required: false
    # Default: eu-west-2

    active-region-count:
    # Number of region slots to deploy. Must be the slot count or the slot count minus
    # one; see the reference architecture README for why.
    #
    # Required: false
    # Default: 3

    kubernetes-version:
    # Version of Kubernetes to install
    #
    # Required: false
    # Default: 1.36

    np-desired-node-count:
    # Desired number of nodes per regional node group
    #
    # Required: false
    # Default: 3

    single-nat-gateway:
    # Whether to use a single NAT gateway per region. True in CI to save on IPs.
    #
    # Required: false
    # Default: true

    database-instance-class:
    # Aurora instance class. Kept small in CI.
    #
    # Required: false
    # Default: db.r6g.large

    tags:
    # Tags to apply to every resource, in JSON format
    #
    # Required: false
    # Default: {}

    s3-backend-bucket:
    # Name of the S3 bucket storing the Terraform state
    #
    # Required: true
    # Default: ""

    s3-bucket-region:
    # Region of the bucket containing the state; falls back on aws-region
    #
    # Required: false
    # Default: ""

    s3-bucket-key-prefix:
    # Key prefix inside the state bucket. Must end with a '/'.
    #
    # Required: false
    # Default: ""

    ref-arch:
    # Reference architecture directory under aws/kubernetes
    #
    # Required: false
    # Default: eks-multi-region-rdbms
```

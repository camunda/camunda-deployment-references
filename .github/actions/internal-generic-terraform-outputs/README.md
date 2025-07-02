# Generic Terraform Outputs

## Description

Initializes Terraform and exposes all outputs as GitHub Action outputs.
Consume as following:
string: fromJson(steps.terraform-outputs.outputs.json_output).bastion_ip.value
array:  toJson(fromJson(steps.terraform-outputs.outputs.json_output).camunda_ips.value)
Or directly in your workflow by interacting with the initialized state.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tf-state-suffix` | <p>The suffix of the terraform state, quite often the cluster name</p> | `true` | `""` |
| `tf-modules-name` | <p>Name of the Terraform module to use, the folder to refer to - cluster / vpn</p> | `true` | `cluster` |
| `s3-backend-bucket` | <p>Name of the S3 bucket to store Terraform state</p> | `true` | `""` |
| `s3-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on aws-region</p> | `false` | `""` |
| `s3-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |


## Outputs

| name | description |
| --- | --- |
| `json_output` | <p>All Terraform outputs as a JSON string</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-generic-terraform-outputs@main
  with:
    tf-state-suffix:
    # The suffix of the terraform state, quite often the cluster name
    #
    # Required: true
    # Default: ""

    tf-modules-name:
    # Name of the Terraform module to use, the folder to refer to - cluster / vpn
    #
    # Required: true
    # Default: cluster

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
```

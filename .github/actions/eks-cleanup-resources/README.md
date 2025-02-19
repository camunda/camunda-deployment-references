# Delete EKS resources

## Description

This GitHub Action automates the deletion of EKS resources using a shell script.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tf-bucket` | <p>Bucket containing the resources states</p> | `true` | `""` |
| `tf-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on AWS_REGION</p> | `false` | `""` |
| `max-age-hours` | <p>Maximum age of resources in hours</p> | `false` | `20` |
| `target` | <p>Specify an ID to destroy specific resources or "all" to destroy all resources</p> | `false` | `all` |
| `temp-dir` | <p>Temporary directory prefix used for storing resource data during processing</p> | `false` | `./tmp/eks-cleanup/` |
| `module-name` | <p>Name of the module to destroy (e.g., "eks-cluster", "aurora", "opensearch"), or "all" to destroy all modules</p> | `false` | `all` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-tf-eks-module/.github/actions/eks-cleanup-resources@main
  with:
    tf-bucket:
    # Bucket containing the resources states
    #
    # Required: true
    # Default: ""

    tf-bucket-region:
    # Region of the bucket containing the resources states, if not set, will fallback on AWS_REGION
    #
    # Required: false
    # Default: ""

    max-age-hours:
    # Maximum age of resources in hours
    #
    # Required: false
    # Default: 20

    target:
    # Specify an ID to destroy specific resources or "all" to destroy all resources
    #
    # Required: false
    # Default: all

    temp-dir:
    # Temporary directory prefix used for storing resource data during processing
    #
    # Required: false
    # Default: ./tmp/eks-cleanup/

    module-name:
    # Name of the module to destroy (e.g., "eks-cluster", "aurora", "opensearch"), or "all" to destroy all modules
    #
    # Required: false
    # Default: all
```

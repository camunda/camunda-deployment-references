# Delete Azure AKS Single Region Clusters

## Description

This GitHub Action automates the deletion of azure/kubernetes/aks-single-region reference architecture clusters using a shell script.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tf-bucket` | <p>Bucket containing the clusters states</p> | `true` | `""` |
| `tf-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on AWS_REGION</p> | `false` | `""` |
| `tf-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `max-age-hours-cluster` | <p>Maximum age of clusters in hours</p> | `false` | `12` |
| `target` | <p>Resource group target, specify an ID to destroy specific resources or "all" to destroy all resources</p> | `false` | `all` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/azure-kubernetes-aks-single-region-cleanup@main
  with:
    tf-bucket:
    # Bucket containing the clusters states
    #
    # Required: true
    # Default: ""

    tf-bucket-region:
    # Region of the bucket containing the resources states, if not set, will fallback on AWS_REGION
    #
    # Required: false
    # Default: ""

    tf-bucket-key-prefix:
    # Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.
    #
    # Required: false
    # Default: ""

    max-age-hours-cluster:
    # Maximum age of clusters in hours
    #
    # Required: false
    # Default: 12

    target:
    # Resource group target, specify an ID to destroy specific resources or "all" to destroy all resources
    #
    # Required: false
    # Default: all
```

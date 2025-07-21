# Delete AWS Terraform States for Single Regions

## Description

This GitHub Action automates the deletion of any aws single-region reference architecture states using a shell script.
For this it's using a generic dummy config.tf that is granted access to the TF state and then has auth to AWS to destroy all resources.
## Notes
Not yet dual-region compatible maybe with v6 and single provider declaration, otherwise needs both providers explicitly declared with their alias.
Not yet Azure compatible with state on AWS. One could make it work as long as the Azure authentication is done prior and some provider specifics defined (subscription id).


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tf-bucket` | <p>Bucket containing the states states</p> | `true` | `""` |
| `tf-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on AWS_REGION</p> | `false` | `""` |
| `tf-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `max-age-hours-states` | <p>Maximum age of states in hours</p> | `false` | `12` |
| `target` | <p>Specify an ID to destroy specific resources or "all" to destroy all resources</p> | `false` | `all` |
| `fail-on-not-found` | <p>Whether to fail if no matching resources are found (only for target not 'all')</p> | `false` | `true` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-generic-single-region-cleanup@main
  with:
    tf-bucket:
    # Bucket containing the states states
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

    max-age-hours-states:
    # Maximum age of states in hours
    #
    # Required: false
    # Default: 12

    target:
    # Specify an ID to destroy specific resources or "all" to destroy all resources
    #
    # Required: false
    # Default: all

    fail-on-not-found:
    # Whether to fail if no matching resources are found (only for target not 'all')
    #
    # Required: false
    # Default: true
```

# Delete AWS Resources with Terraform

## Description

This GitHub Action automates the deletion of generic terraform resources using a shell script.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tf-bucket` | <p>Bucket containing the resources</p> | `true` | `""` |
| `tf-bucket-region` | <p>Region of the bucket containing the resources states, if not set, will fallback on AWS_REGION</p> | `false` | `""` |
| `tf-bucket-key-prefix` | <p>Key prefix of the bucket containing the resources states. It must contain a / at the end e.g 'my-prefix/'.</p> | `false` | `""` |
| `max-age-hours` | <p>Maximum age of the resources in hours</p> | `false` | `12` |
| `target` | <p>Specify an ID to destroy specific resources or "all" to destroy all resources</p> | `false` | `all` |
| `fail-on-not-found` | <p>Whether to fail if no matching resources are found (only for target not 'all')</p> | `false` | `true` |
| `modules-order` | <p>Destruction order of modules, e.g. "vpn,cluster" or "cluster,vpn"</p> | `true` | `""` |
| `openshift` | <p>Whether to install OpenShift tooling (ROSA CLI + oc)</p> | `false` | `false` |
| `rosa-cli-version` | <p>Version of the ROSA CLI to use</p> | `false` | `latest` |
| `openshift-version` | <p>Version of the OpenShift to install</p> | `true` | `4.20.3` |
| `delete-ghost-rosa-clusters` | <p>Specify whether to delete ghost rosa clusters (true or false)</p> | `false` | `false` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-generic-terraform-cleanup@main
  with:
    tf-bucket:
    # Bucket containing the resources
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

    max-age-hours:
    # Maximum age of the resources in hours
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

    modules-order:
    # Destruction order of modules, e.g. "vpn,cluster" or "cluster,vpn"
    #
    # Required: true
    # Default: ""

    openshift:
    # Whether to install OpenShift tooling (ROSA CLI + oc)
    #
    # Required: false
    # Default: false

    rosa-cli-version:
    # Version of the ROSA CLI to use
    #
    # Required: false
    # Default: latest

    openshift-version:
    # Version of the OpenShift to install
    #
    # Required: true
    # Default: 4.20.3

    delete-ghost-rosa-clusters:
    # Specify whether to delete ghost rosa clusters (true or false)
    #
    # Required: false
    # Default: false
```

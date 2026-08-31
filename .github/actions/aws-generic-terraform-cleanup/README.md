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
| `openshift-version` | <p>Version of the OpenShift to install</p> | `true` | `4.22.5` |
| `delete-ghost-rosa-clusters` | <p>Specify whether to delete ghost rosa clusters (true or false)</p> | `false` | `false` |
| `destroy-pass-timeout-minutes` | <p>Wall-clock budget for each of the two destroy passes. Keep <code>2 x this value</code>, plus room for the ghost pass and the log upload, under the caller's step-level <code>timeout-minutes</code>. Nothing enforces the relationship, and a step the runner kills takes the log upload down with it — which is how the 2026-08-29 EC2 and ECS cleanups ended with no artifact and no verdict. The default is sized for the daily cleanups' <code>timeout-minutes: 125</code>; a caller on a shorter leash has to lower it to match, or it gets no protection at all.</p> | `false` | `55` |


## Outputs

| name | description |
| --- | --- |
| `stuck-rosa-clusters` | <p>Comma-separated names of the ROSA clusters this run stopped trying to delete because they have been on the cleanup's candidate list for longer than the threshold (24h by default). OCM still owns their teardown, so they are reported rather than failing the cleanup. Empty when nothing is stuck.</p> |


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
    # Default: 4.22.5

    delete-ghost-rosa-clusters:
    # Specify whether to delete ghost rosa clusters (true or false)
    #
    # Required: false
    # Default: false

    destroy-pass-timeout-minutes:
    # Wall-clock budget for each of the two destroy passes.
    # Keep `2 x this value`, plus room for the ghost pass and the log upload, under the
    # caller's step-level `timeout-minutes`. Nothing enforces the relationship, and a step
    # the runner kills takes the log upload down with it — which is how the 2026-08-29 EC2
    # and ECS cleanups ended with no artifact and no verdict. The default is sized for the
    # daily cleanups' `timeout-minutes: 125`; a caller on a shorter leash has to lower it
    # to match, or it gets no protection at all.
    #
    # Required: false
    # Default: 55
```

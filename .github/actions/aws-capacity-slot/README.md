# AWS Capacity Slot

## Description

Bounds how many runs of a suite hold AWS resources at the same time. `acquire` waits until every listed region has room under the account quotas for what the run creates, then takes one of `slots` slots in a pool stored in S3 (atomic conditional writes, lease with expiry, no daily reset). `release` frees the slot; call it with `if: always()` after the destroy steps. The AWS CLI must already be configured.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `mode` | <p><code>acquire</code> or <code>release</code>.</p> | `true` | `""` |
| `pool` | <p>Pool name. Runs sharing a pool share its slots.</p> | `true` | `""` |
| `slots` | <p>Number of runs allowed to hold the pool at the same time.</p> | `false` | `3` |
| `slot-key` | <p>Slot to free, from the <code>slot-key</code> output of <code>acquire</code>. Release mode only. When empty, <code>release</code> frees the slot this run and <code>leg</code> hold, so a separate cleanup job can call it.</p> | `false` | `""` |
| `bucket` | <p>S3 bucket holding the slots, under <code>ci-locks/&lt;pool&gt;/</code>. Keep the default: suites only see each other's reservations in the same bucket.</p> | `false` | `tests-ra-aws-rosa-hcp-tf-state-eu-central-1` |
| `bucket-region` | <p>Region of the bucket.</p> | `false` | `eu-central-1` |
| `lease-minutes` | <p>Lease of a slot. A run that dies without releasing frees its slot after this delay. Must cover the whole job.</p> | `false` | `360` |
| `wait-minutes` | <p>How long <code>acquire</code> waits for capacity before failing.</p> | `false` | `90` |
| `regions` | <p>Space-separated regions to check for free quota. Empty skips the check.</p> | `false` | `""` |
| `needs` | <p>What one run creates in each region of <code>regions</code>, one <code>&lt;resource&gt;=&lt;count&gt;</code> per line. Resources: <code>rds-clusters</code>, <code>rds-instances</code>, <code>vpcs</code>, <code>elastic-ips</code>, <code>transit-gateways</code>, <code>albs</code>, <code>nlbs</code>, <code>eks-clusters</code>, <code>opensearch-domains</code>.</p> | `false` | `""` |
| `provision-minutes` | <p>How long after admission a run may still be creating its resources. Until then, its <code>needs</code> are reserved on top of the current usage when another run is admitted, in every pool, so suites sharing a region see each other. Resources a run has already created are counted twice until then, so keep it short. 30 covers the cluster and network creation; later resources, such as the load balancers of the EKS integration job, count through the real usage and the margin only. The slot records this value, so runs from other branches judge it by its own window.</p> | `false` | `30` |
| `margin` | <p>Units of each quota to keep free for other suites sharing the account.</p> | `false` | `2` |
| `leg` | <p>Tells apart the holders of one run: matrix legs, or jobs sharing a pool. The owner is the run id plus this value, so <code>release</code> may run in a later job of the same run. Pass the same value to <code>acquire</code> and <code>release</code>.</p> | `false` | `""` |


## Outputs

| name | description |
| --- | --- |
| `slot-key` | <p>S3 key of the acquired slot.</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-capacity-slot@main
  with:
    mode:
    # `acquire` or `release`.
    #
    # Required: true
    # Default: ""

    pool:
    # Pool name. Runs sharing a pool share its slots.
    #
    # Required: true
    # Default: ""

    slots:
    # Number of runs allowed to hold the pool at the same time.
    #
    # Required: false
    # Default: 3

    slot-key:
    # Slot to free, from the `slot-key` output of `acquire`. Release mode only. When empty, `release` frees the slot this run and `leg` hold, so a separate cleanup job can call it.
    #
    # Required: false
    # Default: ""

    bucket:
    # S3 bucket holding the slots, under `ci-locks/<pool>/`. Keep the default: suites only see each other's reservations in the same bucket.
    #
    # Required: false
    # Default: tests-ra-aws-rosa-hcp-tf-state-eu-central-1

    bucket-region:
    # Region of the bucket.
    #
    # Required: false
    # Default: eu-central-1

    lease-minutes:
    # Lease of a slot. A run that dies without releasing frees its slot after this delay. Must cover the whole job.
    #
    # Required: false
    # Default: 360

    wait-minutes:
    # How long `acquire` waits for capacity before failing.
    #
    # Required: false
    # Default: 90

    regions:
    # Space-separated regions to check for free quota. Empty skips the check.
    #
    # Required: false
    # Default: ""

    needs:
    # What one run creates in each region of `regions`, one `<resource>=<count>` per line. Resources: `rds-clusters`, `rds-instances`, `vpcs`, `elastic-ips`, `transit-gateways`, `albs`, `nlbs`, `eks-clusters`, `opensearch-domains`.
    #
    # Required: false
    # Default: ""

    provision-minutes:
    # How long after admission a run may still be creating its resources. Until then, its `needs` are reserved on top of the current usage when another run is admitted, in every pool, so suites sharing a region see each other. Resources a run has already created are counted twice until then, so keep it short. 30 covers the cluster and network creation; later resources, such as the load balancers of the EKS integration job, count through the real usage and the margin only. The slot records this value, so runs from other branches judge it by its own window.
    #
    # Required: false
    # Default: 30

    margin:
    # Units of each quota to keep free for other suites sharing the account.
    #
    # Required: false
    # Default: 2

    leg:
    # Tells apart the holders of one run: matrix legs, or jobs sharing a pool. The owner is the run id plus this value, so `release` may run in a later job of the same run. Pass the same value to `acquire` and `release`.
    #
    # Required: false
    # Default: ""
```

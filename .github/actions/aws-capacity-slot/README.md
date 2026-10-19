# AWS Capacity Slot

## Description

Bounds how many runs of a suite hold AWS resources at the same time. `acquire` waits until every listed region has room for the run's RDS clusters under the account quota, then takes one of `slots` slots in a pool stored in S3 (atomic conditional writes, lease with expiry, no daily reset). `release` frees the slot; call it with `if: always()` after the destroy steps. The AWS CLI must already be configured.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `mode` | <p><code>acquire</code> or <code>release</code>.</p> | `true` | `""` |
| `pool` | <p>Pool name. Runs sharing a pool share its slots.</p> | `true` | `""` |
| `slots` | <p>Number of runs allowed to hold the pool at the same time.</p> | `false` | `3` |
| `slot-key` | <p>Slot to free, from the <code>slot-key</code> output of <code>acquire</code>. Release mode only.</p> | `false` | `""` |
| `bucket` | <p>S3 bucket holding the slots, under <code>ci-locks/&lt;pool&gt;/</code>.</p> | `true` | `""` |
| `bucket-region` | <p>Region of the bucket.</p> | `true` | `""` |
| `lease-minutes` | <p>Lease of a slot. A run that dies without releasing frees its slot after this delay. Must cover the whole job.</p> | `false` | `360` |
| `wait-minutes` | <p>How long <code>acquire</code> waits for capacity before failing.</p> | `false` | `45` |
| `rds-regions` | <p>Space-separated regions to check for free RDS cluster quota. Empty skips the check.</p> | `false` | `""` |
| `rds-clusters-needed` | <p>RDS clusters this run creates in each region of <code>rds-regions</code>.</p> | `false` | `0` |
| `rds-margin` | <p>RDS clusters to keep free for other suites sharing the account.</p> | `false` | `5` |


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
    # Slot to free, from the `slot-key` output of `acquire`. Release mode only.
    #
    # Required: false
    # Default: ""

    bucket:
    # S3 bucket holding the slots, under `ci-locks/<pool>/`.
    #
    # Required: true
    # Default: ""

    bucket-region:
    # Region of the bucket.
    #
    # Required: true
    # Default: ""

    lease-minutes:
    # Lease of a slot. A run that dies without releasing frees its slot after this delay. Must cover the whole job.
    #
    # Required: false
    # Default: 360

    wait-minutes:
    # How long `acquire` waits for capacity before failing.
    #
    # Required: false
    # Default: 45

    rds-regions:
    # Space-separated regions to check for free RDS cluster quota. Empty skips the check.
    #
    # Required: false
    # Default: ""

    rds-clusters-needed:
    # RDS clusters this run creates in each region of `rds-regions`.
    #
    # Required: false
    # Default: 0

    rds-margin:
    # RDS clusters to keep free for other suites sharing the account.
    #
    # Required: false
    # Default: 5
```

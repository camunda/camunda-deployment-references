# Debug failed ECS tasks

## Description

Collect debug info from an ECS cluster (services, tasks, stopped reasons, CloudWatch logs) and upload as artifact

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>The ECS cluster name or ARN to inspect</p> | `true` | `""` |
| `aws-region` | <p>The AWS region the cluster lives in</p> | `true` | `""` |
| `log-group-prefix` | <p>CloudWatch log group name prefix to fetch logs from. If empty, defaults to <code>/ecs/&lt;cluster-name without trailing -cluster&gt;</code>.</p> | `false` | `""` |
| `log-tail-lines` | <p>Number of CloudWatch log lines to display per stream in the CI output (full logs are uploaded as artifact)</p> | `false` | `200` |
| `max-stopped-tasks` | <p>Maximum number of recently-stopped tasks to inspect per service (and additionally for standalone tasks not owned by any service, e.g. one-off <code>RunTask</code> invocations).</p> | `false` | `20` |
| `artifact-suffix` | <p>Suffix appended to the artifact name (e.g. scenario/declination identifier)</p> | `false` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-debug-failed-ecs-tasks@main
  with:
    cluster-name:
    # The ECS cluster name or ARN to inspect
    #
    # Required: true
    # Default: ""

    aws-region:
    # The AWS region the cluster lives in
    #
    # Required: true
    # Default: ""

    log-group-prefix:
    # CloudWatch log group name prefix to fetch logs from.
    # If empty, defaults to `/ecs/<cluster-name without trailing -cluster>`.
    #
    # Required: false
    # Default: ""

    log-tail-lines:
    # Number of CloudWatch log lines to display per stream in the CI output (full logs are uploaded as artifact)
    #
    # Required: false
    # Default: 200

    max-stopped-tasks:
    # Maximum number of recently-stopped tasks to inspect per service (and additionally for
    # standalone tasks not owned by any service, e.g. one-off `RunTask` invocations).
    #
    # Required: false
    # Default: 20

    artifact-suffix:
    # Suffix appended to the artifact name (e.g. scenario/declination identifier)
    #
    # Required: false
    # Default: ""
```

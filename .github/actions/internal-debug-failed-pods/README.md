# Debug failed Pods

## Description

Collect debug info from failed pods (CrashLoopBackOff, Error, not ready) and upload logs and cluster state as an artifact

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>The Kubernetes namespace to inspect</p> | `true` | `""` |
| `context` | <p>The kubectl context to use (for multi-cluster setups). If empty, the current context is used.</p> | `false` | `""` |
| `log-tail-lines` | <p>Number of log tail lines shown inline in the CI output; the artifact keeps up to artifact-log-tail-lines per container</p> | `false` | `200` |
| `artifact-log-tail-lines` | <p>Max log lines per container kept in the artifact and scanned for the root cause; bounds runaway/noisy logs</p> | `false` | `100000` |
| `artifact-suffix` | <p>Suffix appended to the artifact name (e.g. scenario/declination identifier)</p> | `false` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-debug-failed-pods@main
  with:
    namespace:
    # The Kubernetes namespace to inspect
    #
    # Required: true
    # Default: ""

    context:
    # The kubectl context to use (for multi-cluster setups). If empty, the current context is used.
    #
    # Required: false
    # Default: ""

    log-tail-lines:
    # Number of log tail lines shown inline in the CI output; the artifact keeps up to artifact-log-tail-lines per container
    #
    # Required: false
    # Default: 200

    artifact-log-tail-lines:
    # Max log lines per container kept in the artifact and scanned for the root cause; bounds runaway/noisy logs
    #
    # Required: false
    # Default: 100000

    artifact-suffix:
    # Suffix appended to the artifact name (e.g. scenario/declination identifier)
    #
    # Required: false
    # Default: ""
```

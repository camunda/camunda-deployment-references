# Restart CoreDNS

## Description

Restart CoreDNS deployment to clear DNS cache for domain-based deployments. Works with both Kubernetes and OpenShift.

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-type` | <p>Type of cluster: kubernetes or openshift</p> | `false` | `kubernetes` |
| `timeout-minutes` | <p>Timeout in minutes for the CoreDNS restart operation</p> | `false` | `10` |
| `stabilization-wait` | <p>Additional wait time in seconds for CoreDNS to stabilize after restart</p> | `false` | `120` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-restart-coredns@main
  with:
    cluster-type:
    # Type of cluster: kubernetes or openshift
    #
    # Required: false
    # Default: kubernetes

    timeout-minutes:
    # Timeout in minutes for the CoreDNS restart operation
    #
    # Required: false
    # Default: 10

    stabilization-wait:
    # Additional wait time in seconds for CoreDNS to stabilize after restart
    #
    # Required: false
    # Default: 120
```

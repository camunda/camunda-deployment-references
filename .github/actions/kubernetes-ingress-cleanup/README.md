# Kubernetes Ingress Cleanup

## Description

Clean up ingress-nginx, external-dns, and cert-manager components from Kubernetes clusters

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `wait-for-dns-cleanup` | <p>Whether to wait for external-dns to clean up domain records before uninstalling</p> | `false` | `true` |
| `dns-cleanup-wait-seconds` | <p>Number of seconds to wait for DNS cleanup</p> | `false` | `45` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-ingress-cleanup@main
  with:
    wait-for-dns-cleanup:
    # Whether to wait for external-dns to clean up domain records before uninstalling
    #
    # Required: false
    # Default: true

    dns-cleanup-wait-seconds:
    # Number of seconds to wait for DNS cleanup
    #
    # Required: false
    # Default: 45
```

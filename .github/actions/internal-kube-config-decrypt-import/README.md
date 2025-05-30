# Decrypt and Login to Kubernetes Cluster

## Description

This action decrypts a base64-encoded, AES-256-CBC encrypted kubeconfig file
and writes it to the kube config location, then verifies the current context
and lists the nodes in the cluster.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `encrypted_kubeconfig_base64` | <p>Base64-encoded encrypted kubeconfig</p> | `true` | `""` |
| `encryption_key` | <p>Encryption key to decrypt the kubeconfig</p> | `true` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-kube-config-decrypt-import@main
  with:
    encrypted_kubeconfig_base64:
    # Base64-encoded encrypted kubeconfig
    #
    # Required: true
    # Default: ""

    encryption_key:
    # Encryption key to decrypt the kubeconfig
    #
    # Required: true
    # Default: ""
```

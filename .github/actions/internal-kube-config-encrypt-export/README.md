# Export and Encrypt Kubeconfig

## Description

This action exports the current Kubernetes configuration (kubeconfig) using `kubectl config view --raw`, then encrypts the file with openssl using AES-256-CBC and a provided encryption key. The encrypted output is base64-encoded for easy and secure transmission as an output.
This ensures secure handling of the kubeconfig file, useful for passing it safely between jobs in a GitHub Actions workflow without exposing sensitive data.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `encryption_key` | <p>Encryption key to encrypt the kubeconfig</p> | `true` | `""` |


## Outputs

| name | description |
| --- | --- |
| `kubeconfig_encrypted` | <p>Base64-encoded encrypted kubeconfig file</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-kube-config-encrypt-export@main
  with:
    encryption_key:
    # Encryption key to encrypt the kubeconfig
    #
    # Required: true
    # Default: ""
```

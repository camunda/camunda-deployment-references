# Generic File Encryption and Export

## Description

This GitHub Action encrypts a specified file using OpenSSL with AES-256-CBC, and returns the encrypted content base64-encoded. Useful for securely handling sensitive files in workflows.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `file_path` | <p>Path to the file to encrypt</p> | `true` | `""` |
| `encryption_key` | <p>Encryption key to encrypt the file</p> | `true` | `""` |


## Outputs

| name | description |
| --- | --- |
| `encrypted_file_base64` | <p>Base64-encoded encrypted file content</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-generic-encrypt-export@main
  with:
    file_path:
    # Path to the file to encrypt
    #
    # Required: true
    # Default: ""

    encryption_key:
    # Encryption key to encrypt the file
    #
    # Required: true
    # Default: ""
```

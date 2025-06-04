# Generic File Decryption

## Description

This GitHub Action decrypts a base64-encoded, AES-256-CBC encrypted file
and writes the decrypted content to a specified output path.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `encrypted_file_base64` | <p>Base64-encoded encrypted file content</p> | `true` | `""` |
| `encryption_key` | <p>Encryption key to decrypt the file</p> | `true` | `""` |
| `output_path` | <p>Path where the decrypted file will be saved</p> | `true` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-generic-decrypt-import@main
  with:
    encrypted_file_base64:
    # Base64-encoded encrypted file content
    #
    # Required: true
    # Default: ""

    encryption_key:
    # Encryption key to decrypt the file
    #
    # Required: true
    # Default: ""

    output_path:
    # Path where the decrypted file will be saved
    #
    # Required: true
    # Default: ""
```

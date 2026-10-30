# Encrypted artifact upload

## Description

Pack files into a tar.gz archive, encrypt it with OpenSSL AES-256-CBC (PBKDF2, same parameters as internal-generic-encrypt-export) and upload it as a workflow artifact. The repository is public, so every artifact is downloadable by any GitHub user. Nothing is uploaded when the key is empty. Decrypt with: openssl enc -d -aes-256-cbc -pbkdf2 -in artifact.tar.gz.enc -pass env:CI_ENCRYPTION_KEY | tar -xz


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `name` | <p>Artifact name</p> | `true` | `""` |
| `path` | <p>Newline-separated files, directories or glob patterns to pack</p> | `true` | `""` |
| `encryption-key` | <p>Encryption key (CI<em>ENCRYPTION</em>KEY from Vault)</p> | `true` | `""` |
| `retention-days` | <p>Artifact retention in days</p> | `false` | `7` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-encrypted-upload-artifact@main
  with:
    name:
    # Artifact name
    #
    # Required: true
    # Default: ""

    path:
    # Newline-separated files, directories or glob patterns to pack
    #
    # Required: true
    # Default: ""

    encryption-key:
    # Encryption key (CI_ENCRYPTION_KEY from Vault)
    #
    # Required: true
    # Default: ""

    retention-days:
    # Artifact retention in days
    #
    # Required: false
    # Default: 7
```

# Terraform Golden Plan Comparison

## Description

This GitHub Action compares the generated Terraform plan with a golden file. It regenerates the golden file, uploads the result, checks for differences, and comments on the PR if changes are detected. If no changes exist, it removes any previous diff comment.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `module-dir` | <p>Module Directory</p> | `true` | `""` |
| `s3-bucket-region` | <p>S3 Bucket Region</p> | `true` | `""` |
| `s3-backend-bucket` | <p>S3 Backend Bucket</p> | `true` | `""` |
| `s3-bucket-key` | <p>S3 Bucket Key</p> | `true` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-terraform-golden-plan@main
  with:
    module-dir:
    # Module Directory
    #
    # Required: true
    # Default: ""

    s3-bucket-region:
    # S3 Bucket Region
    #
    # Required: true
    # Default: ""

    s3-backend-bucket:
    # S3 Backend Bucket
    #
    # Required: true
    # Default: ""

    s3-bucket-key:
    # S3 Bucket Key
    #
    # Required: true
    # Default: ""
```

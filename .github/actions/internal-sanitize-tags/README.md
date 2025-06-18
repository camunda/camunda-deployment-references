# Sanitize Tags

## Description

This GitHub Action sanitizes the tags given as input and outputs a sanitized version. It's based on the AWS guidelines for tag keys and values, ensuring that tags are compliant with the expected format.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `raw-tags` | <p>Raw tags to sanitize</p> | `false` | `{}` |


## Outputs

| name | description |
| --- | --- |
| `sanitized_tags` | <p>Sanitized tags</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-sanitize-tags@main
  with:
    raw-tags:
    # Raw tags to sanitize
    #
    # Required: false
    # Default: {}
```

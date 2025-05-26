# Create and Apply a Skip Label

## Description

Creates a label named skip_<workflow_file_name> and applies it to the current PR if it doesn't exist. Adds a comment to the PR explaining the label. This action requeries you to provide a ``GH_TOKEN with `write` permission on `pull-requests`.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `comment-message` | <p>The custom message to include in the PR comment.</p> | `false` | `because the tests passed successfully and Renovate is not expected to modify the test logic. This is to save resources. If you are making more significant changes, you should remove the label. 🔄` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-apply-skip-label@main
  with:
    comment-message:
    # The custom message to include in the PR comment.
    #
    # Required: false
    # Default: because the tests passed successfully and Renovate is not expected to modify the test logic. This is to save resources. If you are making more significant changes, you should remove the label. 🔄
```

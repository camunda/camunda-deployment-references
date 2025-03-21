# Skip Workflow if Labeled

## Description

Skips the workflow if a label matches its filename

## Outputs

| name | description |
| --- | --- |
| `should_skip` | <p>Indicates whether the workflow should be skipped</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-triage-skip@main
```

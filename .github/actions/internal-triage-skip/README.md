# Skip Workflow if Labeled

## Description

Skips the workflow if a label matches its filename (e.g.  skip_aws_openshift_rosa_hcp_single_region_tests without the yml extension)


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

# Skip Workflow if Labeled

## Description

Skips the workflow if a label matches its filename (e.g. skip_aws_openshift_rosa_hcp_single_region_tests), or if the corresponding checkbox is checked in the auto-posted checklist comment. Also posts a checklist comment with all available skip options (created once, preserved thereafter).


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

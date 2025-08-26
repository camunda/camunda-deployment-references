# Terraform Drift Detection

## Description

Runs `terraform plan -detailed-exitcode` after an apply to detect immediate drift/flapping.
Fails when drift is detected (config flapping) unless disabled via input.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `working-directory` | <p>Directory where Terraform has been initialized for this stack</p> | `true` | `""` |
| `plan-extra-args` | <p>Extra arguments to append to <code>terraform plan</code> (e.g. -var, -var-file). If using multiline input add a \ for the last line as well.</p> | `false` | `""` |
| `fail-on-drift` | <p>Fail the job when drift is detected (exit code 2)</p> | `false` | `true` |


## Outputs

| name | description |
| --- | --- |
| `drift-detected` | <p>Whether drift was detected by the plan (true/false)</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-terraform-drift-detect@main
  with:
    working-directory:
    # Directory where Terraform has been initialized for this stack
    #
    # Required: true
    # Default: ""

    plan-extra-args:
    # Extra arguments to append to `terraform plan` (e.g. -var, -var-file).
    # If using multiline input add a \ for the last line as well.
    #
    # Required: false
    # Default: ""

    fail-on-drift:
    # Fail the job when drift is detected (exit code 2)
    #
    # Required: false
    # Default: true
```

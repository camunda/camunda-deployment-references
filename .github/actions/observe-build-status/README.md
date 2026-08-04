# Observe Build Status

## Description

Records the build status remotely for analytic purposes

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `build_status` | <p>The status of the job, one of: success, failure, aborted, cancelled</p> | `true` | `""` |
| `user_reason` | <p>Optional string (200 chars max) the user can submit to indicate the reason why a build ended with a certain status.</p> | `false` | `""` |
| `user_description` | <p>Optional string (200 chars max) for the build entry. When empty, falls back to the TEST_OWNER environment variable.</p> | `false` | `""` |
| `job_name` | <p>Optional string, the job whose status is being observed; defaults to $GITHUB_JOB when omitted</p> | `false` | `""` |
| `detailed_junit_tests` | <p>Optional boolean, if true search for TEST-*.xml files and submit their details to dedicated analytics endpoint</p> | `false` | `false` |
| `secret_vault_address` | <p>Vault server URL</p> | `false` | `""` |
| `secret_vault_jwt_path` | <p>Vault JWT auth mount path</p> | `false` | `""` |
| `secret_vault_jwt_role` | <p>Vault JWT auth role</p> | `false` | `""` |
| `secret_vault_jwt_audience` | <p>Vault JWT GitHub audience</p> | `false` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/observe-build-status@main
  with:
    build_status:
    # The status of the job, one of: success, failure, aborted, cancelled
    #
    # Required: true
    # Default: ""

    user_reason:
    # Optional string (200 chars max) the user can submit to indicate the reason why a build ended with a certain status.
    #
    # Required: false
    # Default: ""

    user_description:
    # Optional string (200 chars max) for the build entry. When empty, falls back to the TEST_OWNER environment variable.
    #
    # Required: false
    # Default: ""

    job_name:
    # Optional string, the job whose status is being observed; defaults to $GITHUB_JOB when omitted
    #
    # Required: false
    # Default: ""

    detailed_junit_tests:
    # Optional boolean, if true search for TEST-*.xml files and submit their details to dedicated analytics endpoint
    #
    # Required: false
    # Default: false

    secret_vault_address:
    # Vault server URL
    #
    # Required: false
    # Default: ""

    secret_vault_jwt_path:
    # Vault JWT auth mount path
    #
    # Required: false
    # Default: ""

    secret_vault_jwt_role:
    # Vault JWT auth role
    #
    # Required: false
    # Default: ""

    secret_vault_jwt_audience:
    # Vault JWT GitHub audience
    #
    # Required: false
    # Default: ""
```

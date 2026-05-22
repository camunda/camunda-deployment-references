# Internal — Camunda CI basic-auth credentials

## Description

Fetches a shared Camunda basic-auth user/password from Vault and exposes
them to the workflow so that publicly reachable CI deployments never run
with the chart/config default `demo:demo` credentials (see incident
INC-5340).

Outputs:
- The credentials are exported to `$GITHUB_ENV` as `CAMUNDA_BASIC_AUTH_USER`
  and `CAMUNDA_BASIC_AUTH_PASSWORD` (written via the GITHUB_ENV heredoc
  form so the values are never interpolated into the shell source).
- A Helm overlay values file (JSON, which is valid YAML for helm) is
  written at `${{ runner.temp }}/ci-camunda-basic-auth.json` with
  init-user overrides for the `camunda-platform` chart, with `0600`
  perms. Its path is exposed as the `values-file` step output, so
  callers can append it to their `helm -f` invocation (or to a
  multi-region tests `extra-values-yaml` input) to make the deployed
  chart use the Vault credentials.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `vault-addr` | <p>Vault address (typically secrets.VAULT_ADDR).</p> | `true` | `""` |
| `vault-role-id` | <p>Vault AppRole role id (typically secrets.VAULT<em>ROLE</em>ID).</p> | `true` | `""` |
| `vault-secret-id` | <p>Vault AppRole secret id (typically secrets.VAULT<em>SECRET</em>ID).</p> | `true` | `""` |
| `vault-secret-path` | <p>Vault KV v2 data path holding the basic-auth credentials. Defaults to the shared <code>ci/common</code> secret already used by other workflows: its <code>CI_CAMUNDA_USER_TEST_CLIENT_ID</code> / <code>CI_CAMUNDA_USER_TEST_CLIENT_SECRET</code> keys are reused here as the Camunda basic-auth username/password (the chart provisions a local user matching them via the generated overlay values).</p> | `false` | `secret/data/products/infrastructure-experience/ci/common` |


## Outputs

| name | description |
| --- | --- |
| `values-file` | <p>Path of the generated Helm overlay values file.</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-camunda-ci-credentials@main
  with:
    vault-addr:
    # Vault address (typically secrets.VAULT_ADDR).
    #
    # Required: true
    # Default: ""

    vault-role-id:
    # Vault AppRole role id (typically secrets.VAULT_ROLE_ID).
    #
    # Required: true
    # Default: ""

    vault-secret-id:
    # Vault AppRole secret id (typically secrets.VAULT_SECRET_ID).
    #
    # Required: true
    # Default: ""

    vault-secret-path:
    # Vault KV v2 data path holding the basic-auth credentials.
    # Defaults to the shared `ci/common` secret already used by other
    # workflows: its `CI_CAMUNDA_USER_TEST_CLIENT_ID` /
    # `CI_CAMUNDA_USER_TEST_CLIENT_SECRET` keys are reused here as the
    # Camunda basic-auth username/password (the chart provisions a local
    # user matching them via the generated overlay values).
    #
    # Required: false
    # Default: secret/data/products/infrastructure-experience/ci/common
```

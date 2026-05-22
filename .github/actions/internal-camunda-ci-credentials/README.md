# Internal — Camunda CI basic-auth credentials

## Description

Fetches a shared Camunda basic-auth user/password from Vault and exposes
them to the workflow so that publicly reachable CI deployments never run
with the chart/config default `demo:demo` credentials (see incident
INC-5340).

Outputs:
- The credentials are exported to `$GITHUB_ENV` as `CAMUNDA_BASIC_AUTH_USER`
  and `CAMUNDA_BASIC_AUTH_PASSWORD`.
- A Helm overlay values file is written at `${{ runner.temp }}/ci-camunda-basic-auth.yml`
  with init-user overrides for the `camunda-platform` chart. Its path is
  exported as `CAMUNDA_BASIC_AUTH_VALUES_FILE` env var and as the
  `values-file` step output, so callers can append it to their `helm`
  / `--values` invocation (or to a multi-region tests `extra-values-yaml`
  input) to make the deployed chart use the Vault credentials.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `vault-addr` | <p>Vault address (typically secrets.VAULT_ADDR).</p> | `true` | `""` |
| `vault-role-id` | <p>Vault AppRole role id (typically secrets.VAULT<em>ROLE</em>ID).</p> | `true` | `""` |
| `vault-secret-id` | <p>Vault AppRole secret id (typically secrets.VAULT<em>SECRET</em>ID).</p> | `true` | `""` |
| `vault-secret-path` | <p>Vault KV v2 data path holding the <code>CAMUNDA_BASIC_AUTH_USER</code> and <code>CAMUNDA_BASIC_AUTH_PASSWORD</code> keys. Defaults to the shared CI secret used across all reference-architecture workflows.</p> | `false` | `secret/data/products/infrastructure-experience/ci/global-camunda-basic-auth` |


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
    # Vault KV v2 data path holding the `CAMUNDA_BASIC_AUTH_USER` and
    # `CAMUNDA_BASIC_AUTH_PASSWORD` keys. Defaults to the shared CI
    # secret used across all reference-architecture workflows.
    #
    # Required: false
    # Default: secret/data/products/infrastructure-experience/ci/global-camunda-basic-auth
```

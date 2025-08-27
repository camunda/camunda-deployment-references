# Run C8 Orchestration Cluster E2E tests (sparse checkout)

## Description

Sparsely checks out the QA E2E suite from camunda/camunda at a specific branch, installs dependencies, configures env, runs Playwright tests, and uploads junit results.

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `camunda-repo` | <p>Repository to checkout</p> | `false` | `camunda/camunda` |
| `camunda-ref` | <p>Branch or tag of camunda/camunda to test (e.g. main, stable/8.7)</p> | `false` | `main` |
| `node-version` | <p>Node.js version to use</p> | `false` | `lts` |
| `project` | <p>Playwright project to run</p> | `false` | `chromium` |
| `artifact-name` | <p>Name of the uploaded junit artifact</p> | `false` | `junit-report` |
| `artifact-retention-days` | <p>Retention days for the uploaded artifact</p> | `false` | `7` |
| `LOCAL_TEST` | <p>Whether tests assume a local environment</p> | `false` | `false` |
| `CORE_APPLICATION_URL` | <p>Base URL for the Camunda application</p> | `false` | `http://localhost:8080` |
| `CAMUNDA_AUTH_STRATEGY` | <p>Auth strategy for Camunda (BASIC, etc.)</p> | `false` | `BASIC` |
| `CAMUNDA_BASIC_AUTH_USERNAME` | <p>Username for BASIC auth (use secrets in your workflow)</p> | `false` | `demo` |
| `CAMUNDA_BASIC_AUTH_PASSWORD` | <p>Password for BASIC auth (use secrets in your workflow)</p> | `false` | `demo` |
| `ZEEBE_REST_ADDRESS` | <p>Zeebe REST address</p> | `false` | `http://localhost:8080` |
| `extra-env` | <p>Optional extra KEY=VALUE lines to append to .env (multi-line)</p> | `false` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-qa-orchestration-cluster-tests@main
  with:
    camunda-repo:
    # Repository to checkout
    #
    # Required: false
    # Default: camunda/camunda

    camunda-ref:
    # Branch or tag of camunda/camunda to test (e.g. main, stable/8.7)
    #
    # Required: false
    # Default: main

    node-version:
    # Node.js version to use
    #
    # Required: false
    # Default: lts

    project:
    # Playwright project to run
    #
    # Required: false
    # Default: chromium

    artifact-name:
    # Name of the uploaded junit artifact
    #
    # Required: false
    # Default: junit-report

    artifact-retention-days:
    # Retention days for the uploaded artifact
    #
    # Required: false
    # Default: 7

    LOCAL_TEST:
    # Whether tests assume a local environment
    #
    # Required: false
    # Default: false

    CORE_APPLICATION_URL:
    # Base URL for the Camunda application
    #
    # Required: false
    # Default: http://localhost:8080

    CAMUNDA_AUTH_STRATEGY:
    # Auth strategy for Camunda (BASIC, etc.)
    #
    # Required: false
    # Default: BASIC

    CAMUNDA_BASIC_AUTH_USERNAME:
    # Username for BASIC auth (use secrets in your workflow)
    #
    # Required: false
    # Default: demo

    CAMUNDA_BASIC_AUTH_PASSWORD:
    # Password for BASIC auth (use secrets in your workflow)
    #
    # Required: false
    # Default: demo

    ZEEBE_REST_ADDRESS:
    # Zeebe REST address
    #
    # Required: false
    # Default: http://localhost:8080

    extra-env:
    # Optional extra KEY=VALUE lines to append to .env (multi-line)
    #
    # Required: false
    # Default: ""
```

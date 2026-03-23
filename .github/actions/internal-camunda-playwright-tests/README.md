# Camunda Playwright E2E Tests

## Description

Run Playwright-based E2E tests from the camunda-platform-helm repository. Requires the Helm chart to be deployed and cluster access granted. Uses the helm chart's run-e2e-tests.sh script for environment setup and test execution.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `camunda-helm-repo-ref` | <p>Git ref for camunda-platform-helm checkout</p> | `false` | `main` |
| `camunda-helm-repo-path` | <p>Path to clone the Helm chart repository</p> | `false` | `./.camunda_helm_repo` |
| `camunda-version` | <p>The Camunda version (e.g., 8.9). Used to locate the chart directory.</p> | `true` | `""` |
| `test-namespace` | <p>Kubernetes namespace where Camunda is deployed</p> | `false` | `camunda` |
| `test-project` | <p>Playwright test project to run. Options: smoke-tests, full-suite</p> | `false` | `smoke-tests` |
| `test-exclude` | <p>Tests to exclude (passed to --test-exclude flag). Example: 'identity.spec.ts' or 'console.spec.ts|identity.spec.ts'</p> | `false` | `""` |
| `test-auth-type` | <p>Authentication type: keycloak, basic, hybrid. Passed as TEST<em>AUTH</em>TYPE env var.</p> | `false` | `keycloak` |
| `ingress-host` | <p>Override the ingress hostname detection. If set, this value is used instead of auto-detecting from cluster ingress resources. Required for Kind clusters where the domain is configured via /etc/hosts.</p> | `false` | `""` |
| `ignore-tls-errors` | <p>Set to 'true' to disable TLS certificate verification for both Node.js requests and Playwright browser navigation. Required for Kind clusters using self-signed certificates.</p> | `false` | `false` |
| `upload-artifacts` | <p>Whether to upload Playwright test artifacts (report + results)</p> | `false` | `true` |
| `artifact-retention-days` | <p>Number of days to retain test artifacts</p> | `false` | `10` |
| `artifact-name-suffix` | <p>Suffix appended to artifact names for uniqueness in matrix builds. Defaults to run-id and attempt.</p> | `false` | `""` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-camunda-playwright-tests@main
  with:
    camunda-helm-repo-ref:
    # Git ref for camunda-platform-helm checkout
    #
    # Required: false
    # Default: main

    camunda-helm-repo-path:
    # Path to clone the Helm chart repository
    #
    # Required: false
    # Default: ./.camunda_helm_repo

    camunda-version:
    # The Camunda version (e.g., 8.9). Used to locate the chart directory.
    #
    # Required: true
    # Default: ""

    test-namespace:
    # Kubernetes namespace where Camunda is deployed
    #
    # Required: false
    # Default: camunda

    test-project:
    # Playwright test project to run. Options: smoke-tests, full-suite
    #
    # Required: false
    # Default: smoke-tests

    test-exclude:
    # Tests to exclude (passed to --test-exclude flag). Example: 'identity.spec.ts' or 'console.spec.ts|identity.spec.ts'
    #
    # Required: false
    # Default: ""

    test-auth-type:
    # Authentication type: keycloak, basic, hybrid. Passed as TEST_AUTH_TYPE env var.
    #
    # Required: false
    # Default: keycloak

    ingress-host:
    # Override the ingress hostname detection. If set, this value is used instead of auto-detecting from cluster ingress resources. Required for Kind clusters where the domain is configured via /etc/hosts.
    #
    # Required: false
    # Default: ""

    ignore-tls-errors:
    # Set to 'true' to disable TLS certificate verification for both Node.js requests and Playwright browser navigation. Required for Kind clusters using self-signed certificates.
    #
    # Required: false
    # Default: false

    upload-artifacts:
    # Whether to upload Playwright test artifacts (report + results)
    #
    # Required: false
    # Default: true

    artifact-retention-days:
    # Number of days to retain test artifacts
    #
    # Required: false
    # Default: 10

    artifact-name-suffix:
    # Suffix appended to artifact names for uniqueness in matrix builds. Defaults to run-id and attempt.
    #
    # Required: false
    # Default: ""
```

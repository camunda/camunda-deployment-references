# Camunda Smoke Test

## Description

Generate benchmark process data and verify that processes executed successfully. Deploys a Zeebe benchmark job (configurable duration/rate), waits for data propagation, then verifies process instances exist via the Zeebe REST API.
This action runs in-cluster Kubernetes Jobs and requires kubectl access to the target cluster. It uses the camunda-8-benchmark tool for data generation and a lightweight alpine/curl job for verification.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace where Camunda is deployed.</p> | `false` | `camunda` |
| `release-name` | <p>Helm release name for Camunda.</p> | `false` | `camunda` |
| `keycloak-url` | <p>In-cluster Keycloak base URL. Operator-based (default): http://keycloak-service:18080/auth Bitnami sub-charts: http://<release-name>-keycloak:80/auth</p> | `false` | `""` |
| `benchmark-duration` | <p>Benchmark duration in seconds (the benchmark job runs until killed by activeDeadlineSeconds). Default 300 = 5 minutes.</p> | `false` | `300` |
| `benchmark-pi-per-second` | <p>Process instances per second to generate.</p> | `false` | `5` |
| `min-expected-instances` | <p>Minimum number of process instances expected after the benchmark. A low number (default 10) is sufficient for a smoke test — it proves data generation and Zeebe processing work end-to-end.</p> | `false` | `10` |
| `client-secret-name` | <p>Kubernetes Secret name containing identity-admin-client-id and identity-admin-client-secret keys for OIDC authentication.</p> | `false` | `identity-secret-for-components-integration` |
| `propagation-wait-seconds` | <p>Seconds to wait for data to propagate to search indices after the benchmark.</p> | `false` | `60` |
| `zeebe-grpc-address` | <p>Zeebe gRPC address (in-cluster). Defaults to http://<release-name>-zeebe-gateway:26500.</p> | `false` | `""` |
| `zeebe-rest-address` | <p>Zeebe REST API address (in-cluster). Defaults to http://<release-name>-zeebe-gateway:8080.</p> | `false` | `""` |


## Outputs

| name | description |
| --- | --- |
| `benchmark-status` | <p>'success' or 'failed'</p> |
| `verify-status` | <p>'success' or 'failed'</p> |
| `total-instances` | <p>Total process instances found after benchmark.</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/camunda-smoke-test@main
  with:
    namespace:
    # Kubernetes namespace where Camunda is deployed.
    #
    # Required: false
    # Default: camunda

    release-name:
    # Helm release name for Camunda.
    #
    # Required: false
    # Default: camunda

    keycloak-url:
    # In-cluster Keycloak base URL. Operator-based (default): http://keycloak-service:18080/auth Bitnami sub-charts: http://<release-name>-keycloak:80/auth
    #
    # Required: false
    # Default: ""

    benchmark-duration:
    # Benchmark duration in seconds (the benchmark job runs until killed by activeDeadlineSeconds). Default 300 = 5 minutes.
    #
    # Required: false
    # Default: 300

    benchmark-pi-per-second:
    # Process instances per second to generate.
    #
    # Required: false
    # Default: 5

    min-expected-instances:
    # Minimum number of process instances expected after the benchmark. A low number (default 10) is sufficient for a smoke test — it proves data generation and Zeebe processing work end-to-end.
    #
    # Required: false
    # Default: 10

    client-secret-name:
    # Kubernetes Secret name containing identity-admin-client-id and identity-admin-client-secret keys for OIDC authentication.
    #
    # Required: false
    # Default: identity-secret-for-components-integration

    propagation-wait-seconds:
    # Seconds to wait for data to propagate to search indices after the benchmark.
    #
    # Required: false
    # Default: 60

    zeebe-grpc-address:
    # Zeebe gRPC address (in-cluster). Defaults to http://<release-name>-zeebe-gateway:26500.
    #
    # Required: false
    # Default: ""

    zeebe-rest-address:
    # Zeebe REST API address (in-cluster). Defaults to http://<release-name>-zeebe-gateway:8080.
    #
    # Required: false
    # Default: ""
```

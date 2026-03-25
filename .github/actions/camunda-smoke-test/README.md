# Camunda Smoke Test

## Description

Generate process data and verify that processes executed successfully.
Supports three modes: - kubernetes: deploys in-cluster K8s Jobs (benchmark tool + verify) - http-basic: calls Zeebe REST API directly from runner with basic auth - http-oidc: calls Zeebe REST API with OIDC client_credentials token
For Kubernetes (EKS, AKS, ROSA, Kind, operator-based):
  Uses camunda-8-benchmark K8s Job for data generation and a
  lightweight verify Job for checking process instances.

For HTTP (ECS Fargate, EC2):
  Deploys a BPMN process and creates instances via Zeebe REST API v2
  directly from the GitHub Actions runner through ALB/NLB endpoints.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `mode` | <p>Execution mode. - kubernetes: use in-cluster K8s Jobs (default) - http-basic: use HTTP calls with basic auth (EC2) - http-oidc: use HTTP calls with OIDC token (ECS with Identity)</p> | `false` | `kubernetes` |
| `namespace` | <p>(kubernetes mode) Kubernetes namespace where Camunda is deployed.</p> | `false` | `camunda` |
| `release-name` | <p>(kubernetes mode) Helm release name for Camunda.</p> | `false` | `camunda` |
| `keycloak-url` | <p>(kubernetes mode) In-cluster Keycloak base URL. Operator-based: http://keycloak-service:18080/auth Bitnami: http://<release-name>-keycloak:80/auth</p> | `false` | `""` |
| `client-secret-name` | <p>(kubernetes mode) K8s Secret with identity-admin-client-id and identity-admin-client-secret keys.</p> | `false` | `identity-secret-for-components-integration` |
| `zeebe-grpc-address` | <p>(kubernetes mode) Zeebe gRPC address (in-cluster).</p> | `false` | `""` |
| `zeebe-rest-address` | <p>(kubernetes/http mode) Zeebe REST API address. Kubernetes default: http://<release>-zeebe-gateway:8080 HTTP mode: must be set (e.g., http://<ALB_DNS>)</p> | `false` | `""` |
| `basic-auth-user` | <p>(http-basic mode) Username for basic auth.</p> | `false` | `demo` |
| `basic-auth-password` | <p>(http-basic mode) Password for basic auth.</p> | `false` | `demo` |
| `benchmark-duration` | <p>Benchmark duration in seconds. Default 300 = 5 minutes.</p> | `false` | `300` |
| `benchmark-pi-per-second` | <p>Process instances per second to generate.</p> | `false` | `5` |
| `min-expected-instances` | <p>Minimum process instances expected after the benchmark.</p> | `false` | `10` |
| `propagation-wait-seconds` | <p>Seconds to wait for search index propagation.</p> | `false` | `60` |


## Outputs

| name | description |
| --- | --- |
| `benchmark-status` | <p>'success' or 'failed'</p> |
| `verify-status` | <p>'success' or 'failed'</p> |
| `total-instances` | <p>Total process instances found.</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/camunda-smoke-test@main
  with:
    mode:
    # Execution mode. - kubernetes: use in-cluster K8s Jobs (default) - http-basic: use HTTP calls with basic auth (EC2) - http-oidc: use HTTP calls with OIDC token (ECS with Identity)
    #
    # Required: false
    # Default: kubernetes

    namespace:
    # (kubernetes mode) Kubernetes namespace where Camunda is deployed.
    #
    # Required: false
    # Default: camunda

    release-name:
    # (kubernetes mode) Helm release name for Camunda.
    #
    # Required: false
    # Default: camunda

    keycloak-url:
    # (kubernetes mode) In-cluster Keycloak base URL. Operator-based: http://keycloak-service:18080/auth Bitnami: http://<release-name>-keycloak:80/auth
    #
    # Required: false
    # Default: ""

    client-secret-name:
    # (kubernetes mode) K8s Secret with identity-admin-client-id and identity-admin-client-secret keys.
    #
    # Required: false
    # Default: identity-secret-for-components-integration

    zeebe-grpc-address:
    # (kubernetes mode) Zeebe gRPC address (in-cluster).
    #
    # Required: false
    # Default: ""

    zeebe-rest-address:
    # (kubernetes/http mode) Zeebe REST API address. Kubernetes default: http://<release>-zeebe-gateway:8080 HTTP mode: must be set (e.g., http://<ALB_DNS>)
    #
    # Required: false
    # Default: ""

    basic-auth-user:
    # (http-basic mode) Username for basic auth.
    #
    # Required: false
    # Default: demo

    basic-auth-password:
    # (http-basic mode) Password for basic auth.
    #
    # Required: false
    # Default: demo

    benchmark-duration:
    # Benchmark duration in seconds. Default 300 = 5 minutes.
    #
    # Required: false
    # Default: 300

    benchmark-pi-per-second:
    # Process instances per second to generate.
    #
    # Required: false
    # Default: 5

    min-expected-instances:
    # Minimum process instances expected after the benchmark.
    #
    # Required: false
    # Default: 10

    propagation-wait-seconds:
    # Seconds to wait for search index propagation.
    #
    # Required: false
    # Default: 60
```

# Camunda Smoke Test

## Description

Deploys a BPMN process via Zeebe REST API v2, creates process instances, and verifies they were processed successfully.
For Kubernetes (EKS, AKS, ROSA, Kind, operator-based):
  Automatically sets up kubectl port-forward to access the Zeebe
  gateway and Keycloak from the GitHub Actions runner.

For non-Kubernetes (ECS Fargate, EC2):
  Calls the Zeebe REST API directly through ALB/NLB endpoints.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `zeebe-rest-address` | <p>Zeebe REST API address (e.g., http://<ALB_DNS>). Leave empty for Kubernetes: port-forward is set up automatically.</p> | `false` | `""` |
| `auth-mode` | <p>Authentication mode: oidc, basic, or none.</p> | `false` | `oidc` |
| `namespace` | <p>Kubernetes namespace where Camunda is deployed. Used for kubectl port-forward and secret extraction.</p> | `false` | `camunda` |
| `release-name` | <p>Helm release name for Camunda. Derives service names (e.g., <release>-zeebe-gateway).</p> | `false` | `camunda` |
| `keycloak-url` | <p>In-cluster Keycloak base URL for OIDC auth. Operator: http://keycloak-service:18080/auth Bitnami: http://<release>-keycloak:80/auth</p> | `false` | `""` |
| `client-secret-name` | <p>K8s Secret with identity-admin-client-id and identity-admin-client-secret keys.</p> | `false` | `identity-secret-for-components-integration` |
| `basic-auth-user` | <p>Username for basic auth.</p> | `false` | `demo` |
| `basic-auth-password` | <p>Password for basic auth.</p> | `false` | `demo` |
| `benchmark-duration` | <p>Duration in seconds. Default 300 = 5 minutes.</p> | `false` | `300` |
| `benchmark-pi-per-second` | <p>Process instances per second to generate.</p> | `false` | `5` |
| `min-expected-instances` | <p>Minimum process instances expected.</p> | `false` | `10` |
| `propagation-wait-seconds` | <p>Seconds to wait for search index propagation.</p> | `false` | `60` |


## Outputs

| name | description |
| --- | --- |
| `smoke-test-status` | <p>'success' or 'failed'</p> |
| `total-instances` | <p>Total process instances found.</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/camunda-smoke-test@main
  with:
    zeebe-rest-address:
    # Zeebe REST API address (e.g., http://<ALB_DNS>). Leave empty for Kubernetes: port-forward is set up automatically.
    #
    # Required: false
    # Default: ""

    auth-mode:
    # Authentication mode: oidc, basic, or none.
    #
    # Required: false
    # Default: oidc

    namespace:
    # Kubernetes namespace where Camunda is deployed. Used for kubectl port-forward and secret extraction.
    #
    # Required: false
    # Default: camunda

    release-name:
    # Helm release name for Camunda. Derives service names (e.g., <release>-zeebe-gateway).
    #
    # Required: false
    # Default: camunda

    keycloak-url:
    # In-cluster Keycloak base URL for OIDC auth. Operator: http://keycloak-service:18080/auth Bitnami: http://<release>-keycloak:80/auth
    #
    # Required: false
    # Default: ""

    client-secret-name:
    # K8s Secret with identity-admin-client-id and identity-admin-client-secret keys.
    #
    # Required: false
    # Default: identity-secret-for-components-integration

    basic-auth-user:
    # Username for basic auth.
    #
    # Required: false
    # Default: demo

    basic-auth-password:
    # Password for basic auth.
    #
    # Required: false
    # Default: demo

    benchmark-duration:
    # Duration in seconds. Default 300 = 5 minutes.
    #
    # Required: false
    # Default: 300

    benchmark-pi-per-second:
    # Process instances per second to generate.
    #
    # Required: false
    # Default: 5

    min-expected-instances:
    # Minimum process instances expected.
    #
    # Required: false
    # Default: 10

    propagation-wait-seconds:
    # Seconds to wait for search index propagation.
    #
    # Required: false
    # Default: 60
```

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
| `keycloak-url` | <p>In-cluster Keycloak base URL for OIDC auth. Operator: <code>http://keycloak-service:18080/auth</code> Bitnami: <code>http://&lt;release&gt;-keycloak:80/auth</code></p> | `false` | `""` |
| `oidc-client-id` | <p>OIDC client ID for M2M authentication. If empty, auto-extracted from <release-name>-credentials secret (client ID defaults to 'orchestration').</p> | `false` | `""` |
| `oidc-client-secret` | <p>OIDC client secret for M2M authentication. If empty, auto-extracted from <release-name>-credentials secret (key: identity-orchestration-client-token).</p> | `false` | `""` |
| `oidc-token-url` | <p>OIDC token endpoint URL (e.g., https://<keycloak>/realms/camunda-platform/protocol/openid-connect/token). Required for non-Kubernetes deployments (ECS / EC2) when auth-mode=oidc. In Kubernetes mode this input is ignored — the URL is derived from the auto-port-forwarded Keycloak.</p> | `false` | `""` |
| `basic-auth-user` | <p>Username for basic auth. Required when auth-mode=basic. No default — callers must supply real credentials (see INC-5340).</p> | `false` | `""` |
| `basic-auth-password` | <p>Password for basic auth. Required when auth-mode=basic. No default — callers must supply real credentials (see INC-5340).</p> | `false` | `""` |
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
    # In-cluster Keycloak base URL for OIDC auth. Operator: `http://keycloak-service:18080/auth` Bitnami: `http://<release>-keycloak:80/auth`
    #
    # Required: false
    # Default: ""

    oidc-client-id:
    # OIDC client ID for M2M authentication. If empty, auto-extracted from <release-name>-credentials secret (client ID defaults to 'orchestration').
    #
    # Required: false
    # Default: ""

    oidc-client-secret:
    # OIDC client secret for M2M authentication. If empty, auto-extracted from <release-name>-credentials secret (key: identity-orchestration-client-token).
    #
    # Required: false
    # Default: ""

    oidc-token-url:
    # OIDC token endpoint URL (e.g., https://<keycloak>/realms/camunda-platform/protocol/openid-connect/token). Required for non-Kubernetes deployments (ECS / EC2) when auth-mode=oidc. In Kubernetes mode this input is ignored — the URL is derived from the auto-port-forwarded Keycloak.
    #
    # Required: false
    # Default: ""

    basic-auth-user:
    # Username for basic auth. Required when auth-mode=basic. No default — callers must supply real credentials (see INC-5340).
    #
    # Required: false
    # Default: ""

    basic-auth-password:
    # Password for basic auth. Required when auth-mode=basic. No default — callers must supply real credentials (see INC-5340).
    #
    # Required: false
    # Default: ""

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

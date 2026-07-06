# Camunda Integration Tests (Go)

## Description

Run local Go-based integration tests against a deployed Camunda cluster. Replaces the Venom-based tests that previously required cloning the camunda-platform-helm repository.
Two test suites: 1. Preflight: Health/readiness checks for all components 2. Core: Functional tests (auth, API, process deploy, topology)
Tests run from the GHA runner using port-forward (no-domain) or ingress URLs (domain mode).


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `test-namespace` | <p>Kubernetes namespace where Camunda is deployed</p> | `false` | `camunda` |
| `test-release-name` | <p>Helm release name for Camunda</p> | `false` | `camunda` |
| `test-cluster-type` | <p>Cluster type (kubernetes or openshift)</p> | `false` | `kubernetes` |
| `camunda-domain` | <p>Domain for ingress-based access. Empty = port-forward mode.</p> | `false` | `""` |
| `camunda-domain-grpc` | <p>gRPC domain (e.g. zeebe-domain.example.com:443)</p> | `false` | `""` |
| `auth-mode` | <p>Authentication mode: oidc, basic, or none</p> | `false` | `oidc` |
| `oidc-token-url` | <p>OIDC token endpoint URL</p> | `false` | `""` |
| `oidc-client-id` | <p>OIDC client ID</p> | `false` | `""` |
| `oidc-client-secret` | <p>OIDC client secret</p> | `false` | `""` |
| `oidc-m2m-clients` | <p>JSON map of additional OIDC client<em>id -> client</em>secret pairs to validate via the per-component M2M token test (mirrors the venom "Generating M2M Token" suite). Example: {"connectors":"…","optimize":"…"}</p> | `false` | `""` |
| `basic-auth-user` | <p>Username for basic auth</p> | `false` | `demo` |
| `basic-auth-password` | <p>Password for basic auth</p> | `false` | `demo` |
| `elasticsearch-enabled` | <p>Whether Elasticsearch is enabled</p> | `false` | `true` |
| `webmodeler-enabled` | <p>Whether WebModeler is enabled</p> | `false` | `false` |
| `optimize-enabled` | <p>Whether Optimize is enabled</p> | `false` | `true` |
| `zeebe-gateway-url` | <p>Zeebe gateway URL (for port-forward mode)</p> | `false` | `http://localhost:8080` |
| `keycloak-url` | <p>Keycloak URL (for port-forward mode)</p> | `false` | `http://localhost:18080/auth` |
| `elasticsearch-url` | <p>Elasticsearch URL (for port-forward mode)</p> | `false` | `http://localhost:9200` |
| `retry-attempts` | <p>Number of retry attempts for flaky checks</p> | `false` | `5` |
| `retry-delay` | <p>Delay between retries (Go duration format)</p> | `false` | `10s` |
| `run-preflight` | <p>Whether to run preflight tests</p> | `false` | `true` |
| `run-core` | <p>Whether to run core tests</p> | `false` | `true` |
| `go-test-args` | <p>Additional arguments to pass to go test</p> | `false` | `-v -count=1` |
| `local-domain-mode` | <p>Add /etc/hosts entries so the runner can resolve <code>camunda-domain</code> (and the gRPC variant) to <code>local-domain-ip</code>. Required for Kind + domain mode, where the ingress is reachable through localhost.</p> | `false` | `false` |
| `local-domain-ip` | <p>IP used for local-domain-mode /etc/hosts entries.</p> | `false` | `127.0.0.1` |
| `connectors-service-name` | <p>Service name for Connectors (used to set up port-forward in no-domain mode).</p> | `false` | `camunda-connectors` |
| `connectors-local-port` | <p>Local port to forward Connectors onto (no-domain mode).</p> | `false` | `8081` |
| `connectors-context-path` | <p>Context path under which the Connectors app is exposed (matches helm value <code>connectors.contextPath</code>). Appended to the local connectors URL so /actuator/health/* probes resolve correctly. Leave empty when the chart serves connectors at root.</p> | `false` | `""` |


## Outputs

| name | description |
| --- | --- |
| `preflight-result` | <p>'passed', 'failed', or 'skipped'</p> |
| `core-result` | <p>'passed', 'failed', or 'skipped'</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-integration-tests@main
  with:
    test-namespace:
    # Kubernetes namespace where Camunda is deployed
    #
    # Required: false
    # Default: camunda

    test-release-name:
    # Helm release name for Camunda
    #
    # Required: false
    # Default: camunda

    test-cluster-type:
    # Cluster type (kubernetes or openshift)
    #
    # Required: false
    # Default: kubernetes

    camunda-domain:
    # Domain for ingress-based access. Empty = port-forward mode.
    #
    # Required: false
    # Default: ""

    camunda-domain-grpc:
    # gRPC domain (e.g. zeebe-domain.example.com:443)
    #
    # Required: false
    # Default: ""

    auth-mode:
    # Authentication mode: oidc, basic, or none
    #
    # Required: false
    # Default: oidc

    oidc-token-url:
    # OIDC token endpoint URL
    #
    # Required: false
    # Default: ""

    oidc-client-id:
    # OIDC client ID
    #
    # Required: false
    # Default: ""

    oidc-client-secret:
    # OIDC client secret
    #
    # Required: false
    # Default: ""

    oidc-m2m-clients:
    # JSON map of additional OIDC client_id -> client_secret pairs to validate via the per-component M2M token test (mirrors the venom "Generating M2M Token" suite). Example: {"connectors":"...","optimize":"..."}
    #
    # Required: false
    # Default: ""

    basic-auth-user:
    # Username for basic auth
    #
    # Required: false
    # Default: demo

    basic-auth-password:
    # Password for basic auth
    #
    # Required: false
    # Default: demo

    elasticsearch-enabled:
    # Whether Elasticsearch is enabled
    #
    # Required: false
    # Default: true

    webmodeler-enabled:
    # Whether WebModeler is enabled
    #
    # Required: false
    # Default: false

    optimize-enabled:
    # Whether Optimize is enabled
    #
    # Required: false
    # Default: true

    zeebe-gateway-url:
    # Zeebe gateway URL (for port-forward mode)
    #
    # Required: false
    # Default: http://localhost:8080

    keycloak-url:
    # Keycloak URL (for port-forward mode)
    #
    # Required: false
    # Default: http://localhost:18080/auth

    elasticsearch-url:
    # Elasticsearch URL (for port-forward mode)
    #
    # Required: false
    # Default: http://localhost:9200

    retry-attempts:
    # Number of retry attempts for flaky checks
    #
    # Required: false
    # Default: 5

    retry-delay:
    # Delay between retries (Go duration format)
    #
    # Required: false
    # Default: 10s

    run-preflight:
    # Whether to run preflight tests
    #
    # Required: false
    # Default: true

    run-core:
    # Whether to run core tests
    #
    # Required: false
    # Default: true

    go-test-args:
    # Additional arguments to pass to go test
    #
    # Required: false
    # Default: -v -count=1

    local-domain-mode:
    # Add /etc/hosts entries so the runner can resolve `camunda-domain` (and the gRPC variant) to `local-domain-ip`. Required for Kind + domain mode, where the ingress is reachable through localhost.
    #
    # Required: false
    # Default: false

    local-domain-ip:
    # IP used for local-domain-mode /etc/hosts entries.
    #
    # Required: false
    # Default: 127.0.0.1

    connectors-service-name:
    # Service name for Connectors (used to set up port-forward in no-domain mode).
    #
    # Required: false
    # Default: camunda-connectors

    connectors-local-port:
    # Local port to forward Connectors onto (no-domain mode).
    #
    # Required: false
    # Default: 8081

    connectors-context-path:
    # Context path under which the Connectors app is exposed (matches
    # helm value `connectors.contextPath`). Appended to the local
    # connectors URL so /actuator/health/* probes resolve correctly.
    # Leave empty when the chart serves connectors at root.
    #
    # Required: false
    # Default: ""
```

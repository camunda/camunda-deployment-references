# Camunda Chart Tests

## Description

Run the Camunda Helm chart tests. Already requires the Helm chart to be deployed and cluster access granted.
This action integrates multiple testing layers: 1. Helm chart integration tests (from camunda-platform-helm) 2. C8 Self-Managed checks (from c8-sm-checks repository):
   - Deployment verification (checks pods and containers status)
   - Kubernetes connectivity checks (services and ingress resolution)
   - AWS IRSA configuration checks (for EKS clusters with IRSA)
   - Zeebe token generation and connectivity checks

All C8 SM checks can be individually enabled/disabled via inputs.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `tests-camunda-helm-chart-repo-ref` | <p>The branch, tag or commit to checkout</p> | `false` | `main` |
| `tests-camunda-helm-chart-repo-path` | <p>Path to the Helm chart repository</p> | `false` | `./.camunda_helm_repo` |
| `tests-c8-sm-checks-repo-ref` | <p>The branch, tag or commit to checkout for c8-sm-checks</p> | `false` | `main` |
| `tests-c8-sm-checks-repo-path` | <p>Path to clone the c8-sm-checks repository</p> | `false` | `./.c8-sm-checks` |
| `secrets` | <p>JSON wrapped secrets for easier secret passing</p> | `true` | `""` |
| `camunda-version` | <p>The version of the Camunda to test</p> | `true` | `""` |
| `camunda-domain` | <p>The domain to use for the tests</p> | `false` | `""` |
| `camunda-domain-grpc` | <p>The domain to use for the gRPC tests</p> | `false` | `""` |
| `webmodeler-enabled` | <p>Whether the Webmodeler is enabled in the chart</p> | `false` | `false` |
| `console-enabled` | <p>Whether the Console is enabled in the chart</p> | `false` | `false` |
| `elasticsearch-enabled` | <p>Whether the Elasticsearch is enabled in the chart</p> | `false` | `true` |
| `test-namespace` | <p>The namespace to use for the helm tests</p> | `false` | `camunda` |
| `test-release-name` | <p>The helm release name to used for by the helm tests</p> | `false` | `camunda` |
| `test-cluster-type` | <p>The type of the cluster to use for the tests</p> | `false` | `kubernetes` |
| `zeebe-topology-golden-file` | <p>The golden file to compare the Zeebe topology output against.</p> | `false` | `./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology-output.json` |
| `zeebe-topology-check-script` | <p>The script called to the current Zeebe topology.</p> | `false` | `./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology.sh` |
| `zeebe-authenticated` | <p>Use the authentication layer to interact with zeebe</p> | `false` | `true` |
| `enable-helm-chart-tests` | <p>Whether the Helm Chart tests should be run</p> | `false` | `true` |
| `enable-zeebe-client-tests` | <p>Whether the Zeebe Client tests should be run</p> | `false` | `true` |
| `cluster-2-name` | <p>Optional cluster 2 name for sed replacement (dual-region only)</p> | `false` | `""` |
| `camunda-namespace-2` | <p>Optional namespace for region 2 (dual-region only)</p> | `false` | `""` |
| `camunda-namespace-1` | <p>Optional namespace for region 1 (dual-region only)</p> | `false` | `""` |
| `keycloak-service-name` | <p>Name of the Keycloak service with optional port (e.g. keycloak-service:8080)</p> | `false` | `""` |
| `elasticsearch-service-name` | <p>Name of the Elasticsearch service with optional port (e.g. elasticsearch-es-http:9200)</p> | `false` | `""` |
| `test-client-id` | <p>Client ID for Camunda authentication tests</p> | `true` | `""` |
| `test-client-secret` | <p>Client secret for Camunda authentication tests</p> | `true` | `""` |
| `enable-c8sm-deployment-check` | <p>Whether the C8 SM deployment check should be run</p> | `false` | `true` |
| `enable-c8sm-connectivity-check` | <p>Whether the C8 SM Kubernetes connectivity check should be run</p> | `false` | `true` |
| `skip-c8sm-connectivity-ingress-class-check` | <p>Whether to skip the ingress class check part of the C8 SM Kubernetes connectivity check</p> | `false` | `false` |
| `enable-c8sm-irsa-check` | <p>Whether the C8 SM AWS IRSA check should be run (only applicable for EKS)</p> | `false` | `false` |
| `enable-c8sm-zeebe-token-check` | <p>Whether the C8 SM Zeebe token generation check should be run</p> | `false` | `true` |
| `enable-c8sm-zeebe-connectivity-check` | <p>Whether the C8 SM Zeebe connectivity check should be run</p> | `false` | `true` |
| `local-domain-mode` | <p>Enable local domain mode. When true, /etc/hosts entries will be added to resolve camunda.example.com and zeebe-camunda.example.com to 127.0.0.1. This is required for local Kind clusters with domain-based access where the runner needs to access the ingress via localhost.</p> | `false` | `false` |
| `local-domain-ip` | <p>The IP address to use for local domain resolution in /etc/hosts. Defaults to 127.0.0.1 for standard local development.</p> | `false` | `127.0.0.1` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-camunda-chart-tests@main
  with:
    tests-camunda-helm-chart-repo-ref:
    # The branch, tag or commit to checkout
    #
    # Required: false
    # Default: main

    tests-camunda-helm-chart-repo-path:
    # Path to the Helm chart repository
    #
    # Required: false
    # Default: ./.camunda_helm_repo

    tests-c8-sm-checks-repo-ref:
    # The branch, tag or commit to checkout for c8-sm-checks
    #
    # Required: false
    # Default: main

    tests-c8-sm-checks-repo-path:
    # Path to clone the c8-sm-checks repository
    #
    # Required: false
    # Default: ./.c8-sm-checks

    secrets:
    # JSON wrapped secrets for easier secret passing
    #
    # Required: true
    # Default: ""

    camunda-version:
    # The version of the Camunda to test
    #
    # Required: true
    # Default: ""

    camunda-domain:
    # The domain to use for the tests
    #
    # Required: false
    # Default: ""

    camunda-domain-grpc:
    # The domain to use for the gRPC tests
    #
    # Required: false
    # Default: ""

    webmodeler-enabled:
    # Whether the Webmodeler is enabled in the chart
    #
    # Required: false
    # Default: false

    console-enabled:
    # Whether the Console is enabled in the chart
    #
    # Required: false
    # Default: false

    elasticsearch-enabled:
    # Whether the Elasticsearch is enabled in the chart
    #
    # Required: false
    # Default: true

    test-namespace:
    # The namespace to use for the helm tests
    #
    # Required: false
    # Default: camunda

    test-release-name:
    # The helm release name to used for by the helm tests
    #
    # Required: false
    # Default: camunda

    test-cluster-type:
    # The type of the cluster to use for the tests
    #
    # Required: false
    # Default: kubernetes

    zeebe-topology-golden-file:
    # The golden file to compare the Zeebe topology output against.
    #
    # Required: false
    # Default: ./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology-output.json

    zeebe-topology-check-script:
    # The script called to the current Zeebe topology.
    #
    # Required: false
    # Default: ./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology.sh

    zeebe-authenticated:
    # Use the authentication layer to interact with zeebe
    #
    # Required: false
    # Default: true

    enable-helm-chart-tests:
    # Whether the Helm Chart tests should be run
    #
    # Required: false
    # Default: true

    enable-zeebe-client-tests:
    # Whether the Zeebe Client tests should be run
    #
    # Required: false
    # Default: true

    cluster-2-name:
    # Optional cluster 2 name for sed replacement (dual-region only)
    #
    # Required: false
    # Default: ""

    camunda-namespace-2:
    # Optional namespace for region 2 (dual-region only)
    #
    # Required: false
    # Default: ""

    camunda-namespace-1:
    # Optional namespace for region 1 (dual-region only)
    #
    # Required: false
    # Default: ""

    keycloak-service-name:
    # Name of the Keycloak service with optional port (e.g. keycloak-service:8080)
    #
    # Required: false
    # Default: ""

    elasticsearch-service-name:
    # Name of the Elasticsearch service with optional port (e.g. elasticsearch-es-http:9200)
    #
    # Required: false
    # Default: ""

    test-client-id:
    # Client ID for Camunda authentication tests
    #
    # Required: true
    # Default: ""

    test-client-secret:
    # Client secret for Camunda authentication tests
    #
    # Required: true
    # Default: ""

    enable-c8sm-deployment-check:
    # Whether the C8 SM deployment check should be run
    #
    # Required: false
    # Default: true

    enable-c8sm-connectivity-check:
    # Whether the C8 SM Kubernetes connectivity check should be run
    #
    # Required: false
    # Default: true

    skip-c8sm-connectivity-ingress-class-check:
    # Whether to skip the ingress class check part of the C8 SM Kubernetes connectivity check
    #
    # Required: false
    # Default: false

    enable-c8sm-irsa-check:
    # Whether the C8 SM AWS IRSA check should be run (only applicable for EKS)
    #
    # Required: false
    # Default: false

    enable-c8sm-zeebe-token-check:
    # Whether the C8 SM Zeebe token generation check should be run
    #
    # Required: false
    # Default: true

    enable-c8sm-zeebe-connectivity-check:
    # Whether the C8 SM Zeebe connectivity check should be run
    #
    # Required: false
    # Default: true

    local-domain-mode:
    # Enable local domain mode. When true, /etc/hosts entries will be added to resolve camunda.example.com and zeebe-camunda.example.com to 127.0.0.1. This is required for local Kind clusters with domain-based access where the runner needs to access the ingress via localhost.
    #
    # Required: false
    # Default: false

    local-domain-ip:
    # The IP address to use for local domain resolution in /etc/hosts. Defaults to 127.0.0.1 for standard local development.
    #
    # Required: false
    # Default: 127.0.0.1
```

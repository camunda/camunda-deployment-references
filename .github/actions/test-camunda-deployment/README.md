# Test Camunda Deployment

## Description

Reusable action to test Camunda Platform deployment on Kubernetes

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-type` | <p>Cluster type (kubernetes, openshift)</p> | `false` | `kubernetes` |
| `namespace` | <p>Kubernetes namespace where Camunda is deployed</p> | `true` | `""` |
| `camunda-url` | <p>Base URL of Camunda Platform (e.g. https://camunda.example.com)</p> | `true` | `""` |
| `camunda-version` | <p>Camunda Platform version to test</p> | `false` | `8.8` |
| `test-suites` | <p>Test suites to execute (comma-separated: core,playwright,preflight)</p> | `false` | `core` |
| `skip-elasticsearch` | <p>Skip Elasticsearch tests</p> | `false` | `false` |
| `skip-keycloak` | <p>Skip Keycloak tests</p> | `false` | `false` |
| `skip-webmodeler` | <p>Skip Web Modeler tests</p> | `false` | `true` |
| `test-timeout` | <p>Test timeout (e.g. 30m)</p> | `false` | `20m` |
| `extra-test-args` | <p>Additional test arguments</p> | `false` | `""` |
| `install-tools` | <p>Install required tools (kubectl, helm, task, yq) automatically</p> | `false` | `true` |
| `camunda-username` | <p>Username for Camunda authentication</p> | `false` | `demo` |
| `camunda-password` | <p>Password for Camunda authentication</p> | `false` | `demo` |
| `tests-camunda-helm-chart-repo-ref` | <p>The branch, tag or commit to checkout for tests</p> | `false` | `main` |
| `tests-camunda-helm-chart-repo-path` | <p>Path to the Helm chart repository</p> | `false` | `./.camunda_helm_repo` |
| `enable-zeebe-client-tests` | <p>Whether the Zeebe Client tests should be run</p> | `false` | `true` |
| `zeebe-topology-golden-file` | <p>The golden file to compare the Zeebe topology output against</p> | `false` | `./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology-output.json` |
| `zeebe-topology-check-script` | <p>The script called to check the current Zeebe topology</p> | `false` | `./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology.sh` |
| `zeebe-authenticated` | <p>Use the authentication layer to interact with zeebe</p> | `false` | `true` |
| `test-release-name` | <p>The helm release name used by the tests</p> | `false` | `camunda` |
| `cluster-2-name` | <p>Optional cluster 2 name for sed replacement (dual-region only)</p> | `false` | `""` |
| `camunda-namespace-2` | <p>Optional namespace for region 2 (dual-region only)</p> | `false` | `""` |
| `camunda-namespace-1` | <p>Optional namespace for region 1 (dual-region only)</p> | `false` | `""` |
| `secrets` | <p>JSON wrapped secrets for easier secret passing</p> | `false` | `""` |


## Outputs

| name | description |
| --- | --- |
| `test-results` | <p>Test results</p> |
| `test-logs` | <p>Test logs</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/test-camunda-deployment@main
  with:
    cluster-type:
    # Cluster type (kubernetes, openshift)
    #
    # Required: false
    # Default: kubernetes

    namespace:
    # Kubernetes namespace where Camunda is deployed
    #
    # Required: true
    # Default: ""

    camunda-url:
    # Base URL of Camunda Platform (e.g. https://camunda.example.com)
    #
    # Required: true
    # Default: ""

    camunda-version:
    # Camunda Platform version to test
    #
    # Required: false
    # Default: 8.8

    test-suites:
    # Test suites to execute (comma-separated: core,playwright,preflight)
    #
    # Required: false
    # Default: core

    skip-elasticsearch:
    # Skip Elasticsearch tests
    #
    # Required: false
    # Default: false

    skip-keycloak:
    # Skip Keycloak tests
    #
    # Required: false
    # Default: false

    skip-webmodeler:
    # Skip Web Modeler tests
    #
    # Required: false
    # Default: true

    test-timeout:
    # Test timeout (e.g. 30m)
    #
    # Required: false
    # Default: 20m

    extra-test-args:
    # Additional test arguments
    #
    # Required: false
    # Default: ""

    install-tools:
    # Install required tools (kubectl, helm, task, yq) automatically
    #
    # Required: false
    # Default: true

    camunda-username:
    # Username for Camunda authentication
    #
    # Required: false
    # Default: demo

    camunda-password:
    # Password for Camunda authentication
    #
    # Required: false
    # Default: demo

    tests-camunda-helm-chart-repo-ref:
    # The branch, tag or commit to checkout for tests
    #
    # Required: false
    # Default: main

    tests-camunda-helm-chart-repo-path:
    # Path to the Helm chart repository
    #
    # Required: false
    # Default: ./.camunda_helm_repo

    enable-zeebe-client-tests:
    # Whether the Zeebe Client tests should be run
    #
    # Required: false
    # Default: true

    zeebe-topology-golden-file:
    # The golden file to compare the Zeebe topology output against
    #
    # Required: false
    # Default: ./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology-output.json

    zeebe-topology-check-script:
    # The script called to check the current Zeebe topology
    #
    # Required: false
    # Default: ./generic/kubernetes/single-region/procedure/check-zeebe-cluster-topology.sh

    zeebe-authenticated:
    # Use the authentication layer to interact with zeebe
    #
    # Required: false
    # Default: true

    test-release-name:
    # The helm release name used by the tests
    #
    # Required: false
    # Default: camunda

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

    secrets:
    # JSON wrapped secrets for easier secret passing
    #
    # Required: false
    # Default: ""
```

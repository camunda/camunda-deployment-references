# Deploy Keycloak via Operator

## Description

Deploys Keycloak using the Keycloak Operator with CloudNativePG PostgreSQL.
Uses scripts from generic/kubernetes/operator-based/ for deployment.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace for deployment</p> | `false` | `camunda` |
| `keycloak-mode` | <p>Keycloak deployment mode:</p> <ul> <li>'domain': With ingress for domain access (nginx)</li> <li>'domain-openshift': With ingress for OpenShift router</li> <li>'no-domain': Without ingress (port-forward access)</li> </ul> | `false` | `no-domain` |
| `domain-name` | <p>Domain name (required for domain mode)</p> | `false` | `""` |
| `cnpg-operator-namespace` | <p>Namespace for CNPG operator</p> | `false` | `cnpg-system` |


## Outputs

| name | description |
| --- | --- |
| `keycloak-admin-secret` | <p>Name of the Keycloak admin secret</p> |
| `keycloak-service` | <p>Keycloak service name</p> |
| `keycloak-port` | <p>Keycloak service port</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-keycloak-operator@main
  with:
    namespace:
    # Kubernetes namespace for deployment
    #
    # Required: false
    # Default: camunda

    keycloak-mode:
    # Keycloak deployment mode:
    # - 'domain': With ingress for domain access (nginx)
    # - 'domain-openshift': With ingress for OpenShift router
    # - 'no-domain': Without ingress (port-forward access)
    #
    # Required: false
    # Default: no-domain

    domain-name:
    # Domain name (required for domain mode)
    #
    # Required: false
    # Default: ""

    cnpg-operator-namespace:
    # Namespace for CNPG operator
    #
    # Required: false
    # Default: cnpg-system
```

# Cleanup Keycloak Operator Deployment

## Description

Remove Keycloak deployed via Keycloak Operator and its CNPG PostgreSQL cluster (pg-keycloak)

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace where Keycloak was deployed</p> | `true` | `""` |
| `skip-operator-uninstall` | <p>Skip uninstalling the operators (useful if shared across namespaces)</p> | `false` | `false` |
| `cnpg-operator-namespace` | <p>Namespace for the CNPG operator</p> | `false` | `cnpg-system` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-keycloak-operator-cleanup@main
  with:
    namespace:
    # Kubernetes namespace where Keycloak was deployed
    #
    # Required: true
    # Default: ""

    skip-operator-uninstall:
    # Skip uninstalling the operators (useful if shared across namespaces)
    #
    # Required: false
    # Default: false

    cnpg-operator-namespace:
    # Namespace for the CNPG operator
    #
    # Required: false
    # Default: cnpg-system
```

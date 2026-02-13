# Cleanup Keycloak Operator Deployment

## Description

Remove Keycloak deployed via Keycloak Operator and CNPG PostgreSQL

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace where Keycloak was deployed</p> | `true` | `""` |
| `skip-operator-uninstall` | <p>Skip uninstalling the operators (useful if shared across namespaces)</p> | `false` | `false` |


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
```

# Cleanup Keycloak Operator Deployment

## Description

Remove Keycloak deployed via Keycloak Operator and its CNPG PostgreSQL cluster (pg-keycloak)

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace where Keycloak was deployed</p> | `true` | `""` |


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
```

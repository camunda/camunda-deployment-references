# Cleanup CNPG PostgreSQL Cluster

## Description

Removes a single CloudNativePG PostgreSQL cluster and its secrets.
Optionally uninstalls the CNPG operator.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace where the cluster was deployed</p> | `true` | `""` |
| `cluster-name` | <p>Name of the CNPG cluster to delete (e.g., pg-keycloak, pg-identity, pg-webmodeler)</p> | `true` | `""` |
| `skip-operator-uninstall` | <p>Skip uninstalling the CNPG operator (set to false only if no other clusters remain)</p> | `false` | `true` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-cnpg-cluster-cleanup@main
  with:
    namespace:
    # Kubernetes namespace where the cluster was deployed
    #
    # Required: true
    # Default: ""

    cluster-name:
    # Name of the CNPG cluster to delete (e.g., pg-keycloak, pg-identity, pg-webmodeler)
    #
    # Required: true
    # Default: ""

    skip-operator-uninstall:
    # Skip uninstalling the CNPG operator (set to false only if no other clusters remain)
    #
    # Required: false
    # Default: true
```

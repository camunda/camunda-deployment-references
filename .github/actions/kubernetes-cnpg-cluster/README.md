# Deploy CNPG PostgreSQL Cluster

## Description

Deploys a single CloudNativePG PostgreSQL cluster.
Installs the CNPG operator if not already present (idempotent).
Uses scripts and manifests from generic/kubernetes/operator-based/postgresql/.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace for the PostgreSQL cluster</p> | `false` | `camunda` |
| `cluster-name` | <p>Name of the CNPG cluster to deploy (must match a cluster in postgresql-clusters.yml). Examples: pg-keycloak, pg-identity, pg-webmodeler</p> | `true` | `""` |


## Outputs

| name | description |
| --- | --- |
| `cluster-service` | <p>PostgreSQL read-write service name (e.g., pg-identity-rw)</p> |
| `cluster-service-port` | <p>PostgreSQL service port</p> |
| `cluster-secret` | <p>Name of the bootstrap secret containing credentials</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-cnpg-cluster@main
  with:
    namespace:
    # Kubernetes namespace for the PostgreSQL cluster
    #
    # Required: false
    # Default: camunda

    cluster-name:
    # Name of the CNPG cluster to deploy (must match a cluster in postgresql-clusters.yml).
    # Examples: pg-keycloak, pg-identity, pg-webmodeler
    #
    # Required: true
    # Default: ""
```

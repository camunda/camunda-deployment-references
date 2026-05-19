# Deploy Elasticsearch via ECK Operator

## Description

Deploys Elasticsearch using the Elastic Cloud on Kubernetes (ECK) operator.
Installs the ECK operator if not already present (idempotent).
Uses scripts and manifests from generic/kubernetes/operator-based/elasticsearch/.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `namespace` | <p>Kubernetes namespace for the Elasticsearch cluster</p> | `false` | `camunda` |
| `elasticsearch-cluster-name` | <p>Name of the Elasticsearch cluster (must match the metadata.name of the Elasticsearch resource in the manifest). Used to derive the service and secret names.</p> | `false` | `elasticsearch` |
| `elasticsearch-cluster-file` | <p>Path to the Elasticsearch cluster manifest. Relative to generic/kubernetes/operator-based/elasticsearch/.</p> | `false` | `elasticsearch-cluster.yml` |


## Outputs

| name | description |
| --- | --- |
| `elasticsearch-service` | <p>Elasticsearch service name</p> |
| `elasticsearch-port` | <p>Elasticsearch service port</p> |
| `elasticsearch-secret` | <p>Name of the Elasticsearch elastic user secret</p> |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/kubernetes-eck-operator@main
  with:
    namespace:
    # Kubernetes namespace for the Elasticsearch cluster
    #
    # Required: false
    # Default: camunda

    elasticsearch-cluster-name:
    # Name of the Elasticsearch cluster (must match the metadata.name
    # of the Elasticsearch resource in the manifest). Used to derive
    # the service and secret names.
    #
    # Required: false
    # Default: elasticsearch

    elasticsearch-cluster-file:
    # Path to the Elasticsearch cluster manifest.
    # Relative to generic/kubernetes/operator-based/elasticsearch/.
    #
    # Required: false
    # Default: elasticsearch-cluster.yml
```

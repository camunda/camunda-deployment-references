# Internal Multi-Region Tests

## Description

Run tests across multiple regions

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-0-namespace` | <p>Camunda namespace for Cluster 0</p> | `true` | `camunda-platform` |
| `cluster-1-namespace` | <p>Camunda namespace for Cluster 1</p> | `true` | `camunda-platform` |
| `helm-version` | <p>Helm version to test</p> | `true` | `""` |
| `cluster-0-name` | <p>Name of cluster in region 0</p> | `true` | `""` |
| `cluster-1-name` | <p>Name of cluster in region 1</p> | `true` | `""` |
| `backup-name` | <p>Name of the backup that should be created, important in shared s3 buckets</p> | `false` | `""` |
| `backup-bucket` | <p>Name of the S3 bucket where backups are stored</p> | `false` | `camunda-platform-backups` |
| `default-values-yaml` | <p>Path to default values yaml file</p> | `false` | `./aws/kubernetes/eks-dual-region/helm-values/camunda-values.yml` |
| `region-0-values-yaml` | <p>Path to region 0 values yaml file</p> | `false` | `./aws/kubernetes/eks-dual-region/helm-values/region0/camunda-values.yml` |
| `region-1-values-yaml` | <p>Path to region 1 values yaml file</p> | `false` | `./aws/kubernetes/eks-dual-region/helm-values/region1/camunda-values.yml` |
| `extra-values-yaml` | <p>Comma separated string of extra values yaml files to be applied</p> | `false` | `""` |
| `skip-cleanup` | <p>Skip cleanup step only (keep deploy to ensure test process is created). Use this when deployment already exists with platform-specific config like OpenShift ServiceExports.</p> | `false` | `false` |
| `post-failback-script` | <p>Script to run after Failback to re-export services (e.g., for OpenShift Submariner ServiceExports)</p> | `false` | `""` |
| `distribution` | <p>Distribution to test on, e.g., EKS or OpenShift. Mainly for disabling certain tests.</p> | `false` | `EKS` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-multi-region-tests@main
  with:
    cluster-0-namespace:
    # Camunda namespace for Cluster 0
    #
    # Required: true
    # Default: camunda-platform

    cluster-1-namespace:
    # Camunda namespace for Cluster 1
    #
    # Required: true
    # Default: camunda-platform

    helm-version:
    # Helm version to test
    #
    # Required: true
    # Default: ""

    cluster-0-name:
    # Name of cluster in region 0
    #
    # Required: true
    # Default: ""

    cluster-1-name:
    # Name of cluster in region 1
    #
    # Required: true
    # Default: ""

    backup-name:
    # Name of the backup that should be created, important in shared s3 buckets
    #
    # Required: false
    # Default: ""

    backup-bucket:
    # Name of the S3 bucket where backups are stored
    #
    # Required: false
    # Default: camunda-platform-backups

    default-values-yaml:
    # Path to default values yaml file
    #
    # Required: false
    # Default: ./aws/kubernetes/eks-dual-region/helm-values/camunda-values.yml

    region-0-values-yaml:
    # Path to region 0 values yaml file
    #
    # Required: false
    # Default: ./aws/kubernetes/eks-dual-region/helm-values/region0/camunda-values.yml

    region-1-values-yaml:
    # Path to region 1 values yaml file
    #
    # Required: false
    # Default: ./aws/kubernetes/eks-dual-region/helm-values/region1/camunda-values.yml

    extra-values-yaml:
    # Comma separated string of extra values yaml files to be applied
    #
    # Required: false
    # Default: ""

    skip-cleanup:
    # Skip cleanup step only (keep deploy to ensure test process is created). Use this when deployment already exists with platform-specific config like OpenShift ServiceExports.
    #
    # Required: false
    # Default: false

    post-failback-script:
    # Script to run after Failback to re-export services (e.g., for OpenShift Submariner ServiceExports)
    #
    # Required: false
    # Default: ""

    distribution:
    # Distribution to test on, e.g., EKS or OpenShift. Mainly for disabling certain tests.
    #
    # Required: false
    # Default: EKS
```

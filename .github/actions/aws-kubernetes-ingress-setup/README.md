# AWS Kubernetes Ingress Setup

## Description

Install and configure ingress-nginx, external-dns, and cert-manager for AWS EKS clusters

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>Name of the cluster (used for external-dns owner ID)</p> | `true` | `""` |
| `scenario-short-name` | <p>Short name of the scenario (used for external-dns owner ID)</p> | `true` | `""` |
| `aws-region` | <p>AWS region where the cluster is deployed</p> | `true` | `eu-west-2` |
| `mail` | <p>Email address for Let's Encrypt certificates</p> | `false` | `admin@camunda.ie` |
| `tld` | <p>Top-level domain for the cluster</p> | `false` | `camunda.ie` |
| `ref-arch` | <p>Reference architecture name (eks-single-region, eks-single-region-irsa)</p> | `false` | `eks-single-region` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/aws-kubernetes-ingress-setup@main
  with:
    cluster-name:
    # Name of the cluster (used for external-dns owner ID)
    #
    # Required: true
    # Default: ""

    scenario-short-name:
    # Short name of the scenario (used for external-dns owner ID)
    #
    # Required: true
    # Default: ""

    aws-region:
    # AWS region where the cluster is deployed
    #
    # Required: true
    # Default: eu-west-2

    mail:
    # Email address for Let's Encrypt certificates
    #
    # Required: false
    # Default: admin@camunda.ie

    tld:
    # Top-level domain for the cluster
    #
    # Required: false
    # Default: camunda.ie

    ref-arch:
    # Reference architecture name (eks-single-region, eks-single-region-irsa)
    #
    # Required: false
    # Default: eks-single-region
```

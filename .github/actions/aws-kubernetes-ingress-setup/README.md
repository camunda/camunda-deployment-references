# AWS Kubernetes Ingress Setup

## Description

Install and configure an ingress controller (ingress-nginx or Contour), external-dns, and cert-manager for AWS EKS clusters

## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `cluster-name` | <p>Name of the cluster (used for external-dns owner ID)</p> | `true` | `""` |
| `scenario-short-name` | <p>Short name of the scenario (used for external-dns owner ID)</p> | `true` | `""` |
| `aws-region` | <p>AWS region where the cluster is deployed</p> | `true` | `eu-west-2` |
| `mail` | <p>Email address for Let's Encrypt certificates</p> | `false` | `admin@camunda.ie` |
| `tld` | <p>Top-level domain for the cluster</p> | `false` | `camunda.ie` |
| `ref-arch` | <p>Reference architecture name (eks-single-region, eks-single-region-irsa)</p> | `false` | `eks-single-region` |
| `ingress-controller` | <p>Which ingress controller to install. One of:</p> <ul> <li>'nginx'   (default) — installs ingress-nginx via Helm</li> <li>'contour' — installs Project Contour via the ref-arch's install-contour.sh</li> </ul> | `false` | `nginx` |
| `use-wildcard-cert` | <p>Use wildcard certificate from Vault instead of ACME/Let's Encrypt. When true, ACME issuer is not installed and wildcard certificate is created from Vault.</p> | `false` | `false` |
| `wildcard-cert-namespace` | <p>Namespace where the wildcard TLS certificate will be created (when use-wildcard-cert is true)</p> | `false` | `camunda` |
| `wildcard-cert-secret-name` | <p>Name of the wildcard TLS secret to create (when use-wildcard-cert is true)</p> | `false` | `camunda-tls` |
| `vault-addr` | <p>Vault server address (required when use-wildcard-cert is true)</p> | `false` | `""` |
| `vault-role-id` | <p>Vault AppRole role ID (required when use-wildcard-cert is true)</p> | `false` | `""` |
| `vault-secret-id` | <p>Vault AppRole secret ID (required when use-wildcard-cert is true)</p> | `false` | `""` |


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

    ingress-controller:
    # Which ingress controller to install. One of:
    #   - 'nginx'   (default) — installs ingress-nginx via Helm
    #   - 'contour' — installs Project Contour via the ref-arch's install-contour.sh
    #
    # Required: false
    # Default: nginx

    use-wildcard-cert:
    # Use wildcard certificate from Vault instead of ACME/Let's Encrypt.
    # When true, ACME issuer is not installed and wildcard certificate is created from Vault.
    #
    # Required: false
    # Default: false

    wildcard-cert-namespace:
    # Namespace where the wildcard TLS certificate will be created (when use-wildcard-cert is true)
    #
    # Required: false
    # Default: camunda

    wildcard-cert-secret-name:
    # Name of the wildcard TLS secret to create (when use-wildcard-cert is true)
    #
    # Required: false
    # Default: camunda-tls

    vault-addr:
    # Vault server address (required when use-wildcard-cert is true)
    #
    # Required: false
    # Default: ""

    vault-role-id:
    # Vault AppRole role ID (required when use-wildcard-cert is true)
    #
    # Required: false
    # Default: ""

    vault-secret-id:
    # Vault AppRole secret ID (required when use-wildcard-cert is true)
    #
    # Required: false
    # Default: ""
```

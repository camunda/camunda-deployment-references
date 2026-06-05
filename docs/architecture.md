# Architecture

## Purpose

This repository provides **reference architectures** for deploying Camunda 8 Self-Managed. Each architecture is a combination of Terraform IaC + Helm values + shell procedures. They serve two use cases:

1. **Reference** — understand the required components and confirm existing setups.
2. **Copy & paste** — fork and extend for real deployments.

The official Camunda docs for these references live at:
- https://docs.camunda.io/docs/self-managed/reference-architecture/
- https://docs.camunda.io/docs/self-managed/deployment/helm/cloud-providers/

## Repository Structure

```
{cloud_provider}/
  modules/                      # Reusable Terraform modules for this provider
  {category}/
    {solution}-{feature}-{declination}/
      terraform/                # Terraform root modules (cluster/, vpn/ subfolders)
      helm-values/              # Helm values files for Camunda platform
      procedure/                # Shell scripts for manual/CI steps
      test/                     # Go integration tests + golden terraform plan fixtures
```

### Cloud Providers

| Folder    | Contents |
|-----------|----------|
| `aws/`    | EKS (single/dual region, IRSA variant), ROSA HCP (single/dual region), ECS Fargate, EC2. Modules: `eks-cluster`, `aurora`, `opensearch`, `rosa-hcp`, `ecs`, `vpn` |
| `azure/`  | AKS (single region, with RDBMS variant). Modules: `aks`, `network`, `kms`, `postgres-db` |
| `generic/`| Cloud-agnostic Kubernetes (single/dual region), OpenShift, operator-based (CNPG, ECK, Keycloak), Debian bare metal |
| `local/`  | Kind (Kubernetes in Docker) for local development |

### Helm Values Patterns

Each deployment's `helm-values/` contains scenario-specific overrides:
- `values-domain.yml` — domain-based ingress
- `values-no-domain.yml` — no-domain setup
- `values-oidc.yml` — OIDC integration
- `values-mkcert.yml` — local TLS with mkcert

## Camunda Architecture

Camunda 8 deployments consist of two logical clusters:

**Orchestration Cluster:**
- Zeebe (workflow engine)
- Operate (monitoring UI)
- Tasklist (human task UI)
- Admin (auth/authz) — named Identity in ≤ 8.8

**Secondary Storage (choose one per deployment, migration between them is not supported):**
- Elasticsearch / OpenSearch (search-heavy workloads)
- RDBMS/PostgreSQL (relational preference)

**Production baseline:** Minimum 3 Zeebe brokers across 3 availability zones.

## Naming Convention

```
{cloud_provider}/{category}/{solution}-{feature}-{declination}
```

Examples:
- `aws/kubernetes/eks-single-region`
- `aws/kubernetes/eks-dual-region`
- `aws/openshift/rosa-hcp-single-region`
- `aws/containers/ecs-single-region-fargate`
- `azure/kubernetes/aks-single-region-rdbms`

## Branching Strategy

- `main` = next unreleased Camunda version (active development)
- `stable/8.x` = released versions (patch-only)
- `.camunda-version` = current target version
- `.target-branch` = merge target for PRs (read by CI; update when cutting a release)

Only one version is actively developed at a time. Renovate runs on all active branches.

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
| `aws/`    | EKS (single/dual/multi region, IRSA and RDBMS variants), ROSA HCP (single/dual region, RDBMS declination), ECS Fargate, EC2. Modules: `eks-cluster`, `aurora`, `aurora-global`, `aurora-global-member`, `opensearch`, `rosa-hcp`, `ecs`, `vpn`, `transit-gateway`, `transit-gateway-hub`, `transit-gateway-peering` |
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

**Secondary Storage (choose one family per deployment; in-place migration between families is not supported):**
- Elasticsearch / OpenSearch (search-heavy / analytics workloads)
- RDBMS / PostgreSQL (relational preference; Optimize still requires Elasticsearch/OpenSearch)

RDBMS secondary storage is available since 8.9 for the Orchestration Cluster (Operate, Tasklist, v2 REST API). For backend trade-offs and benchmarks, see [secondary storage architecture](https://docs.camunda.io/docs/self-managed/reference-architecture/reference-architecture/#secondary-storage-architecture) and [RDBMS benchmark results](https://docs.camunda.io/docs/self-managed/concepts/secondary-storage/rdbms-benchmark-results/) in the product documentation. Reference implementations with a dedicated RDBMS variant (the `*-rdbms` declination of a ref-arch uses a relational database instead of a document store):

| Reference architecture | RDBMS backend |
|------------------------|---------------|
| `azure/kubernetes/aks-single-region-rdbms` | Azure Database for PostgreSQL Flexible Server |
| `aws/kubernetes/eks-single-region-rdbms` | Amazon Aurora PostgreSQL |
| `aws/openshift/rosa-hcp-single-region` (`no-domain-rdbms` declination) | CloudNativePG in-cluster PostgreSQL |
| `local/kubernetes/kind-single-region` (`SECONDARY_STORAGE=postgres`) | CloudNativePG in-cluster PostgreSQL |
| `aws/kubernetes/eks-multi-region-rdbms` | Amazon Aurora Global Database (experimental) |

Dual-region deployments are Elasticsearch-only: RDBMS secondary storage is not supported there, because each region populates its own secondary storage through the Camunda exporter. See [dual-region limitations](https://docs.camunda.io/docs/self-managed/concepts/multi-region/dual-region/#limitations). That limit belongs to the two-region topology rather than to RDBMS itself — it comes from running one exporter and one store per region. The multi-region topology below sidesteps it by sharing a single database between all regions.

**Multi-region topologies:**

| Feature | Regions | Secondary storage | Region loss |
|---------|---------|-------------------|-------------|
| `dual-region` | 2 | One Elasticsearch per region, two Camunda exporters | Quorum lost, manual failover then failback with an ES snapshot restore |
| `multi-region` | N (3 by default) | One RDBMS, replication delegated to the database | Quorum preserved, the engine keeps processing |

The RDBMS exporter has [no multi-region mode](https://docs.camunda.io/docs/next/self-managed/concepts/databases/relational-db/database-configuration/#multi-region-support): a single JDBC connection exists per Orchestration Cluster. `multi-region` turns that into the design by making replication the database's responsibility (Aurora Global Database in the AWS reference, any single-writer endpoint elsewhere). Reference implementation: `aws/kubernetes/eks-multi-region-rdbms` — **experimental**; the product documents and supports two regions.

Zeebe places replicas per zone, so the replication factor is the sum of the zones' replicas rather than the number of zones. The AWS reference defaults to two replicas in each database region and one in the remaining region, giving `replicationFactor: 5` across three zones: the third region carries a vote without carrying a database, and losing either database region still leaves three replicas of five. The layout is configurable — any distribution works as long as no single zone holds half the replicas.

**Production baseline:** Minimum 3 Zeebe brokers across 3 availability zones.

## Naming Convention

```
{cloud_provider}/{category}/{solution}-{feature}-{declination}
```

Examples:
- `aws/kubernetes/eks-single-region`
- `aws/kubernetes/eks-dual-region`
- `aws/kubernetes/eks-multi-region-rdbms`
- `aws/openshift/rosa-hcp-single-region`
- `aws/containers/ecs-single-region-fargate`
- `azure/kubernetes/aks-single-region-rdbms`

## Branching Strategy

- `main` = next unreleased Camunda version (active development)
- `stable/8.x` = released versions (patch-only)
- `.camunda-version` = current target version
- `.target-branch` = merge target for PRs (read by CI; update when cutting a release)

Only one version is actively developed at a time. Renovate runs on all active branches.

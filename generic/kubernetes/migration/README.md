# Camunda Migration: Bitnami → Kubernetes Operators

Migrate a Camunda 8 Helm installation from Bitnami-managed infrastructure (PostgreSQL, Elasticsearch, Keycloak) to Kubernetes operator-managed equivalents (CloudNativePG, ECK, Keycloak Operator).

This migration is designed to align your setup with the [operator-based reference architecture](../operator-based/).

> **⚠ IMPORTANT: Customization Responsibility**
>
> The migration scripts deploy operators and instances using the manifests from `operator-based/`.
> **You are responsible for reviewing and customizing these manifests** before running the migration.
>
> In particular, verify:
> - **PostgreSQL clusters** (`operator-based/postgresql/postgresql-clusters.yml`): storage size, replicas, PG version, parameters
> - **Elasticsearch cluster** (`migration/manifests/eck-cluster.yml`): node count, storage, resource limits
> - **Keycloak CR** (`operator-based/keycloak/keycloak-instance-*.yml`): replicas, resource limits, hostname
> - **Helm values** (`operator-based/*/camunda-*-values.yml`): connection settings, secrets
>
> The migration performs basic validation (CPU, memory, PVC sizes) but cannot detect all configuration mismatches.

## Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Migration Phases                              │
│                                                                      │
│  Phase 1 ✦ Deploy Targets     ─── no downtime ──────────────────── │
│    Install operators + create target clusters alongside Bitnami      │
│                                                                      │
│  Phase 2 ✦ Initial Backup     ─── no downtime ──────────────────── │
│    Backup all data while the application is still running            │
│                                                                      │
│  Phase 3 ✦ Cutover            ─── DOWNTIME (5-30 min) ──────────── │
│    Freeze → Final backup → Restore → Helm upgrade → Unfreeze        │
│                                                                      │
│  Phase 4 ✦ Validate           ─── no downtime ──────────────────── │
│    Verify all components are healthy on the new infrastructure       │
└──────────────────────────────────────────────────────────────────────┘
```

## What Gets Migrated

| Source (Bitnami)                  | Target (Operator)             | Data Migrated              |
| --------------------------------- | ----------------------------- | -------------------------- |
| Bitnami PostgreSQL (Identity)     | CloudNativePG cluster         | `pg_dump` / `pg_restore`   |
| Bitnami PostgreSQL (Keycloak)     | CloudNativePG cluster         | `pg_dump` / `pg_restore`   |
| Bitnami PostgreSQL (WebModeler)   | CloudNativePG cluster         | `pg_dump` / `pg_restore`   |
| Bitnami Elasticsearch             | ECK Elasticsearch             | Snapshot API               |
| Bitnami Keycloak (Helm sub-chart) | Keycloak Operator CR          | Via PostgreSQL data        |

## Prerequisites

- A running Camunda 8 installation using the Helm chart with Bitnami sub-charts
- `kubectl` configured for the target cluster
- `helm` v3 with `camunda/camunda-platform` repo added
- `envsubst` available (usually included in `gettext`)
- `jq` installed
- `yq` installed (for selective CNPG cluster deployment)
- Sufficient cluster resources to run both old and new infrastructure temporarily
- The `operator-based/` directory must be present alongside `migration/`

## Directory Structure

```
generic/kubernetes/
├── operator-based/                  # Reference architecture (reused by migration)
│   ├── postgresql/
│   │   ├── deploy.sh               #   CNPG operator + cluster deployment
│   │   ├── set-secrets.sh          #   PostgreSQL secret management
│   │   ├── postgresql-clusters.yml #   ★ CUSTOMIZE: PG cluster specs
│   │   ├── camunda-identity-values.yml
│   │   └── camunda-webmodeler-values.yml
│   ├── elasticsearch/
│   │   ├── deploy.sh               #   ECK operator + cluster deployment
│   │   ├── elasticsearch-cluster.yml
│   │   └── camunda-elastic-values.yml
│   └── keycloak/
│       ├── deploy.sh               #   Keycloak operator + CR deployment
│       ├── keycloak-instance-*.yml #   ★ CUSTOMIZE: Keycloak CR specs
│       ├── camunda-keycloak-domain-values.yml
│       └── camunda-keycloak-no-domain-values.yml
│
└── migration/                       # Migration scripts (this directory)
    ├── env.sh                       # Configuration (edit before starting)
    ├── lib.sh                       # Shared library (do not edit)
    ├── 1-deploy-targets.sh          # Phase 1: Deploy operators + clusters
    ├── 2-backup.sh                  # Phase 2: Initial backup
    ├── 3-cutover.sh                 # Phase 3: Freeze → Restore → Switch
    ├── 4-validate.sh                # Phase 4: Validate everything
    ├── rollback.sh                  # Emergency rollback
    ├── jobs/                        # Kubernetes Job templates
    │   ├── pg-backup.job.yml        #   PostgreSQL backup (generic)
    │   ├── pg-restore.job.yml       #   PostgreSQL restore (generic)
    │   ├── es-backup.job.yml        #   Elasticsearch snapshot backup
    │   └── es-restore.job.yml       #   Elasticsearch snapshot restore
    └── manifests/                   # Migration-specific manifests only
        ├── backup-pvc.yml           #   Shared backup PVC
        └── eck-cluster.yml          #   ECK cluster with snapshot repo support
```

## Quick Start

```bash
# 1. Configure
vi env.sh                    # Edit namespace, release name, domain, versions
source env.sh

# 2. Deploy target infrastructure (no downtime)
bash 1-deploy-targets.sh

# 3. Take initial backup (no downtime)
bash 2-backup.sh

# 4. Cutover (downtime window)
bash 3-cutover.sh

# 5. Validate
bash 4-validate.sh
```

## Configuration

Edit `env.sh` before starting. Key variables:

| Variable                     | Default         | Description                                  |
| ---------------------------- | --------------- | -------------------------------------------- |
| `NAMESPACE`                  | `camunda`       | Kubernetes namespace                         |
| `CAMUNDA_RELEASE_NAME`       | `camunda`       | Helm release name                            |
| `CAMUNDA_HELM_CHART_VERSION` | (chart version) | Target Helm chart version                    |
| `CAMUNDA_DOMAIN`             | (empty)         | Domain for Keycloak Ingress (empty = no TLS) |
| `MIGRATE_IDENTITY`           | `true`          | Migrate Identity PostgreSQL                  |
| `MIGRATE_KEYCLOAK`           | `true`          | Migrate Keycloak + its PostgreSQL            |
| `MIGRATE_WEBMODELER`         | `true`          | Migrate WebModeler PostgreSQL                |
| `MIGRATE_ELASTICSEARCH`      | `true`          | Migrate Elasticsearch                        |

Set any `MIGRATE_*` to `false` to skip a component (e.g. if it's not deployed or already uses an external service).

## Detailed Phase Descriptions

### Phase 1: Deploy Targets (`1-deploy-targets.sh`)

**Downtime: NONE** — Runs alongside the live application.

Delegates to the `operator-based/` deploy scripts to install operators and create target resources:
- Calls `operator-based/postgresql/deploy.sh` for CNPG operator + PG clusters
- Calls `operator-based/elasticsearch/deploy.sh` for ECK operator + ES cluster (using a migration-specific manifest with snapshot repository support)
- Calls `operator-based/keycloak/deploy.sh` for Keycloak operator + CR

Before deploying, the script:
1. Displays a customization warning reminding you to review operator-based manifests
2. Validates target resource allocations (CPU, memory, PVC sizes) against your current Bitnami StatefulSets

All targets are created empty and idle — no traffic is routed to them yet.

### Phase 2: Initial Backup (`2-backup.sh`)

**Downtime: NONE** — Backs up while the application is running.

Creates Kubernetes Jobs that:
- Run `pg_dump` against each Bitnami PostgreSQL instance
- Create an Elasticsearch snapshot of all indices

These "warm" backups reduce the cutover window. A final consistent backup is taken in Phase 3 after the application is frozen.

### Phase 3: Cutover (`3-cutover.sh`)

**Downtime: YES** — Typically 5–30 minutes depending on data volume.

Sequence:
1. **Save** current Helm values (for rollback)
2. **Freeze** all Camunda deployments (scale to 0)
3. **Final backup** with no active connections (consistent state)
4. **Restore** data to new operator-managed targets
5. **Helm upgrade** to point Camunda at the new backends

The Helm upgrade re-enables the deployments, so components restart automatically on the new infrastructure.

### Phase 4: Validate (`4-validate.sh`)

**Downtime: NONE**

Checks:
- All Camunda deployments and StatefulSets are ready
- CNPG clusters are in healthy state
- ECK Elasticsearch is ready with indices
- Keycloak CR is ready

### Rollback (`rollback.sh`)

Restores the pre-cutover Helm values, re-enabling Bitnami sub-charts. The operator-managed resources are left in place (not deleted) so you can retry or debug.

## Downtime Estimation

| Data Volume | Estimated Downtime |
| ----------- | ------------------ |
| < 1 GB      | ~5 minutes         |
| 1-10 GB     | ~10-15 minutes     |
| 10-50 GB    | ~15-30 minutes     |
| > 50 GB     | 30+ minutes        |

The main factor is the `pg_restore` and ES snapshot restore duration.

## Precautions

1. **Test in staging first** — Run the full migration on a non-production environment
2. **Schedule a maintenance window** — Phase 3 requires downtime
3. **Check cluster capacity** — During Phase 1-2, both old and new infrastructure run simultaneously
4. **Backup your Helm values** — Done automatically in Phase 3, but consider an extra manual backup
5. **Monitor resource quotas** — CNPG and ECK clusters consume additional CPU/memory
6. **Elasticsearch `path.repo`** — The source Bitnami ES must support filesystem snapshots. If it doesn't, you may need to patch the StatefulSet to mount the backup PVC and configure `path.repo`
7. **DNS TTL** — If using a domain for Keycloak, ensure DNS TTL is low before cutover

## Cleanup (post-migration)

After validating the migration, remove old Bitnami resources:

```bash
# Delete old PG StatefulSets and their PVCs
kubectl delete statefulset ${CAMUNDA_RELEASE_NAME}-postgresql -n ${NAMESPACE} --ignore-not-found
kubectl delete statefulset ${CAMUNDA_RELEASE_NAME}-keycloak-postgresql -n ${NAMESPACE} --ignore-not-found
kubectl delete statefulset ${CAMUNDA_RELEASE_NAME}-postgresql-web-modeler -n ${NAMESPACE} --ignore-not-found

# Delete old ES StatefulSet
kubectl delete statefulset ${CAMUNDA_RELEASE_NAME}-elasticsearch-master -n ${NAMESPACE} --ignore-not-found

# Delete old Keycloak StatefulSet
kubectl delete statefulset ${CAMUNDA_RELEASE_NAME}-keycloak -n ${NAMESPACE} --ignore-not-found

# Delete migration backup PVC
kubectl delete pvc migration-backup-pvc -n ${NAMESPACE}

# Delete old PVCs (verify first!)
# kubectl get pvc -n ${NAMESPACE} | grep -E "postgresql|elasticsearch"
```

## Design Principles

- **DRY**: Reuses operator-based deploy scripts and manifests — no duplication of operator installation or Helm values
- **Phase-oriented**: 4 clear phases instead of 28 per-component scripts
- **Idempotent**: Each phase can be re-run safely (checks for existing resources before creating)
- **Kubernetes-native**: All data operations run as Kubernetes Jobs inside the cluster
- **Aligned with reference arch**: Deploys the exact same operators and instances as `operator-based/`
- **Validated**: Basic resource checks (CPU, memory, PVC sizes) before deployment
- **Rollback-safe**: Helm values are backed up before cutover, enabling instant rollback

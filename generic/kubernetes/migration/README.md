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
> - **Elasticsearch cluster** (`operator-based/elasticsearch/elasticsearch-cluster.yml`): node count, storage, resource limits
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
│  Phase 3 ✦ Cutover            ─── DOWNTIME (5–40 min typical) ────── │
│    Freeze → Final backup → Restore → Helm upgrade → Unfreeze        │
│                                                                      │
│  Phase 4 ✦ Validate           ─── no downtime ──────────────────── │
│    Verify all components are healthy on the new infrastructure       │
│                                                                      │
│  Phase 5 ✦ Cleanup Bitnami    ─── no downtime ──────────────────── │
│    Remove old Bitnami resources and re-verify                        │
└──────────────────────────────────────────────────────────────────────┘
```

## What Gets Migrated

| Source (Bitnami)                  | Target (Operator)             | Data Migrated              |
| --------------------------------- | ----------------------------- | -------------------------- |
| Bitnami PostgreSQL (Identity)     | CloudNativePG cluster         | `pg_dump` / `pg_restore`   |
| Bitnami PostgreSQL (Keycloak)     | CloudNativePG cluster         | `pg_dump` / `pg_restore`   |
| Bitnami PostgreSQL (WebModeler)   | CloudNativePG cluster         | `pg_dump` / `pg_restore`   |
| Bitnami Elasticsearch             | ECK Elasticsearch             | Reindex-from-remote (`_reindex`) |
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
    ├── 5-cleanup-bitnami.sh         # Phase 5: Remove old Bitnami resources
    ├── rollback.sh                  # Emergency rollback
    ├── hooks/                       # Custom pre/post phase hooks (see Hooks)
    │   └── README.md                #   Hook documentation
    ├── jobs/                        # Kubernetes Job templates
    │   ├── pg-backup.job.yml        #   PostgreSQL backup (generic)
    │   ├── pg-restore.job.yml       #   PostgreSQL restore (generic)
    │   ├── es-backup.job.yml        #   Elasticsearch backup verification
    │   └── es-restore.job.yml       #   Elasticsearch reindex restore
    ├── manifests/                   # Migration-specific manifests only
    │   └── backup-pvc.yml           #   Shared backup PVC
    ├── .state/                      # Runtime state (gitignored, auto-created)
    └── tests/                       # CI & local test fixtures
        ├── seed-test-data-job.yml   #   Seed job (Zeebe, Keycloak, WebModeler)
        ├── benchmark-job.yml        #   Benchmark job (Zeebe process instances)
        ├── verify-test-data-job.yml #   Verify job (post-migration checks)
        ├── bitnami-values.yml       #   Helm values for Bitnami deployment
        ├── bitnami-values-domain.yml #  Helm values variant with domain/TLS
        └── kind-cluster-config.yaml #   Kind cluster config for local testing
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

# 6. Clean up old Bitnami resources
bash 5-cleanup-bitnami.sh
```

## Configuration

Edit `env.sh` before starting. The file is organized into 4 sections — see comments inside for details.

**General settings:**

| Variable                     | Default         | Description                                  |
| ---------------------------- | --------------- | -------------------------------------------- |
| `NAMESPACE`                  | `camunda`       | Kubernetes namespace                         |
| `CAMUNDA_RELEASE_NAME`       | `camunda`       | Helm release name                            |
| `CAMUNDA_HELM_CHART_VERSION` | (chart version) | Target Helm chart version                    |
| `CAMUNDA_DOMAIN`             | (empty)         | Domain for Keycloak Ingress (empty = no TLS) |
| `IDENTITY_DB_NAME`           | `identity`      | Identity database name (must match source)   |
| `KEYCLOAK_DB_NAME`           | `keycloak`      | Keycloak database name (must match source)   |
| `WEBMODELER_DB_NAME`         | `webmodeler`    | WebModeler database name (must match source) |
| `BACKUP_PVC`                 | `migration-backup-pvc` | PVC name for backup data              |
| `BACKUP_STORAGE_SIZE`        | `50Gi`          | Backup PVC size (must fit all dumps)         |
| `MIGRATE_IDENTITY`           | `true`          | Migrate Identity PostgreSQL                  |
| `MIGRATE_KEYCLOAK`           | `true`          | Migrate Keycloak + its PostgreSQL            |
| `MIGRATE_WEBMODELER`         | `true`          | Migrate WebModeler PostgreSQL                |
| `MIGRATE_ELASTICSEARCH`      | `true`          | Migrate Elasticsearch                        |
| `ES_WARM_REINDEX`            | `false`         | When `true`, Phase 2 pre-copies ES data to the target (no downtime). Phase 3 then runs a fast delta reindex, reducing cutover from O(data-size) to ~5 min. For external targets, you must configure `reindex.remote.whitelist` on the target ES |

Set any `MIGRATE_*` to `false` to skip a component (e.g. if it's not deployed or already uses an external service).

**Target mode:**

| Variable                     | Default         | Description                                  |
| ---------------------------- | --------------- | -------------------------------------------- |
| `PG_TARGET_MODE`             | `operator`      | `operator`: deploy CNPG. `external`: skip deployment, migrate to pre-existing target |
| `ES_TARGET_MODE`             | `operator`      | `operator`: deploy ECK. `external`: skip deployment, point to pre-existing target |

**Operator mode** (when `*_TARGET_MODE=operator`):

| Variable                     | Default           | Description                                  |
| ---------------------------- | ----------------- | -------------------------------------------- |
| `CNPG_OPERATOR_NAMESPACE`    | `cnpg-system`     | Namespace for the CNPG operator              |
| `ECK_OPERATOR_NAMESPACE`     | `elastic-system`  | Namespace for the ECK operator               |
| `CNPG_IDENTITY_CLUSTER`     | `pg-identity`     | CNPG cluster name for Identity               |
| `CNPG_KEYCLOAK_CLUSTER`     | `pg-keycloak`     | CNPG cluster name for Keycloak               |
| `CNPG_WEBMODELER_CLUSTER`   | `pg-webmodeler`   | CNPG cluster name for WebModeler             |
| `ECK_CLUSTER_NAME`          | `elasticsearch`   | ECK Elasticsearch cluster name               |

**External mode** (when `*_TARGET_MODE=external`):

| Variable                        | Default                  | Description                                  |
| ------------------------------- | ------------------------ | -------------------------------------------- |
| `EXTERNAL_PG_*_HOST`            | (empty)                  | PostgreSQL host per component                |
| `EXTERNAL_PG_*_PORT`            | `5432`                   | PostgreSQL port per component                |
| `EXTERNAL_PG_*_SECRET`          | `external-pg-<component>`| K8s Secret containing the password           |
| `EXTERNAL_ES_HOST`              | (empty)                  | Elasticsearch host                           |
| `EXTERNAL_ES_PORT`              | `443`                    | Elasticsearch port                           |
| `EXTERNAL_ES_SECRET`            | `external-es`            | K8s Secret containing the password           |
| `CUSTOM_HELM_VALUES_FILE`       | (empty)                  | Helm values file for external connections    |
| `CUSTOM_KEYCLOAK_CONFIG_FILE`   | (empty)                  | Custom Keycloak CR for external PG           |

### When to use `external` target mode

Set `PG_TARGET_MODE=external` or `ES_TARGET_MODE=external` when the migration **should not** deploy operators or create cluster instances — i.e. when the target already exists:

| Scenario | `*_TARGET_MODE` | Why |
| --- | --- | --- |
| Fresh cluster, no operators installed | `operator` (default) | Scripts install CNPG/ECK + create clusters |
| Operators already installed by a platform team | `external` | Avoids overwriting the operator version (scripts apply a pinned version via `kubectl apply --server-side`) |
| Target is a managed service (RDS, OpenSearch, …) | `external` | No operator needed — data migrates directly to the managed endpoint |

When using `external` mode, you must also provide:
- Connection details: `EXTERNAL_PG_*` or `EXTERNAL_ES_*` variables in `env.sh`
- A `CUSTOM_HELM_VALUES_FILE` with Helm values pointing Camunda at the external targets

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
3. Validates version compatibility (PG major downgrades blocked, ES major.minor must match)

All targets are created empty and idle — no traffic is routed to them yet.

### Phase 2: Initial Backup (`2-backup.sh`)

**Downtime: NONE** — Backs up while the application is running.

Creates Kubernetes Jobs that:
- Run `pg_dump` against each Bitnami PostgreSQL instance
- Create an Elasticsearch snapshot of all indices
- _(optional)_ When `ES_WARM_REINDEX=true`, run a full reindex from source to target ES while the app is still running. This pre-populates the target so Phase 3 only needs a fast delta reindex.

These "warm" backups reduce the cutover window. A final consistent backup is taken in Phase 3 after the application is frozen.

### Phase 3: Cutover (`3-cutover.sh`)

**Downtime: YES** — Typically 5–60 minutes depending on Elasticsearch data volume (see [Downtime Estimation](#downtime-estimation)). With `ES_WARM_REINDEX=true`, downtime is reduced to ~5 minutes regardless of data volume.

Sequence:
1. **Save** current Helm values (for rollback)
2. **Freeze** all Camunda deployments (scale to 0)
3. **Final backup** with no active connections (consistent state)
4. **Restore** data to new operator-managed targets (delta reindex if warm reindex was done in Phase 2)
5. **Sync Keycloak admin credentials** — copies the restored admin password to the operator secret so Keycloak and Identity stay in sync
6. **Helm upgrade** to point Camunda at the new backends and restart all components

### Phase 4: Validate (`4-validate.sh`)

**Downtime: NONE**

Checks:
- All Camunda deployments and StatefulSets are ready
- CNPG clusters are in healthy state
- ECK Elasticsearch is ready with indices
- Keycloak CR is ready

At the end, generates a migration report in `.state/migration-report.md`.

### Phase 5: Cleanup Bitnami (`5-cleanup-bitnami.sh`)

**Downtime: NONE**

> **⚠ DESTRUCTIVE — This phase is irreversible.**
>
> After cleanup, rollback to Bitnami sub-charts is no longer possible.
> Before running this phase, **strongly** consider:
> 1. Take a full backup of all databases (`pg_dumpall` or equivalent)
> 2. Snapshot PVCs or storage volumes (cloud provider snapshots)
> 3. Store backups in cold storage (S3 Glacier, GCS Archive, etc.)
> 4. Keep rollback artifacts in `.state/` as a safety net

Removes old Bitnami sub-chart resources that are no longer used after migration:
- Old PostgreSQL StatefulSets and their PVCs
- Old Elasticsearch StatefulSet and its PVCs
- Old Keycloak StatefulSet
- Migration backup PVC

After cleanup, re-verifies that all Camunda components, operator-managed targets, and test data remain healthy without the old resources.

### Rollback (`rollback.sh`)

Restores the pre-cutover Helm values, re-enabling Bitnami sub-charts. The operator-managed resources are left in place (not deleted) so you can retry or debug.

## Downtime Estimation

Only Phase 3 (cutover) causes downtime. The following estimates are derived from CI benchmarks run on GitHub Actions with Kind clusters.

### Benchmarked scenarios

| Scenario | ES Documents | ES Data Size | PG Data (total) | Phase 3 (downtime) |
| -------- | ------------ | ------------ | --------------- | ------------------ |
| Normal   | ~0           | ~0           | ~31 MB          | **~4 min**         |
| Heavy    | ~6.5M        | ~8.9 GB      | ~31 MB          | **~40 min**        |

### Phase 3 breakdown (heavy scenario — ~8.9 GB ES)

| Step                          | Duration  | Notes                                         |
| ----------------------------- | --------- | --------------------------------------------- |
| Freeze components (scale → 0) | ~10s      | Scale down all deployments and StatefulSets    |
| PG backup (3 databases)       | ~16s      | `pg_dump` Identity + Keycloak + WebModeler     |
| ES backup verification        | ~5s       | Snapshot verification of 50 indices            |
| PG restore (3 databases)      | ~24s      | `pg_restore` to CNPG clusters                 |
| **ES reindex (from remote)**  | **~38 min** | **Dominant factor** — reindex 6.5M docs via `_reindex` API |
| Helm upgrade + restart        | ~2 min    | Reconfigure backends, restart all components   |
| **Total**                     | **~40 min** |                                              |

### Downtime estimation by data volume

| ES Data Volume | Estimated Downtime | Bottleneck                     |
| -------------- | ------------------ | ------------------------------ |
| < 1 GB         | ~5 minutes         | Helm upgrade + pod startup     |
| 1–10 GB        | ~10–40 minutes     | ES reindex-from-remote         |
| 10–50 GB       | ~40 min–2 hours    | ES reindex-from-remote         |
| > 50 GB        | 2+ hours           | ES reindex-from-remote         |

### Key observations

- **Elasticsearch reindex is the dominant factor.** In the heavy scenario, ES reindex accounts for ~95% of the total downtime (~38 min out of ~40 min).
- **PostgreSQL migration is negligible.** Even with 3 databases totaling ~31 MB (Identity 7 MB, Keycloak 13 MB / 1806 rows, WebModeler 11 MB / 102 rows), backup + restore completes in under 40 seconds.
- **Observed ES throughput:** ~2,870 docs/s or ~3.9 MB/s on Kind (GitHub Actions runners). Production clusters with faster storage and network will achieve higher throughput.
- **Largest single index:** `optimize-process-instance-benchmark` (897K docs, 6.8 GB) accounted for ~76% of the ES data volume. Real-world deployments with large Optimize history will see similar patterns.
- **Scaling guideline:** Downtime scales roughly linearly with ES data size. Measure during a staging rehearsal with representative data volumes to get an accurate estimate for your environment.

## Precautions

1. **Test in staging first** — Run the full migration on a non-production environment
2. **Schedule a maintenance window** — Phase 3 requires downtime
3. **Check cluster capacity** — During Phase 1-2, both old and new infrastructure run simultaneously
4. **Backup your Helm values** — Done automatically in Phase 3, but consider an extra manual backup
5. **Monitor resource quotas** — CNPG and ECK clusters consume additional CPU/memory
6. **Elasticsearch connectivity** — The target ECK cluster uses the `_reindex` API to pull data from the source Bitnami ES over HTTP. Both clusters must be reachable within the same namespace.
7. **DNS TTL** — If using a domain for Keycloak, ensure DNS TTL is low before cutover
8. **Keycloak OIDC impact** — Keycloak is the OIDC provider for all Camunda components (and possibly external applications). Migrating to the Keycloak Operator changes the underlying service. To ensure a seamless transition:
   - **Before migration:** Set up a DNS CNAME record pointing to Keycloak (e.g. `keycloak.example.com → camunda-keycloak.namespace.svc`), and reduce the TTL to 60s or less well in advance.
   - **During cutover:** Use a `hooks/post-restore.sh` hook to switch the CNAME target to the new Keycloak Operator service. All applications using Keycloak OIDC will follow the DNS change automatically — no reconfiguration needed.
   - **After validation:** Restore the TTL to a normal value.

   If external applications depend on the same Keycloak realm, coordinate the DNS switch with their teams.

   **Session impact:** The database migration preserves all persistent data (realms, users, clients, signing keys, refresh tokens). Since Keycloak 25+, user sessions are persisted in the database and survive the switch. In-flight authentication flows (login pages in progress) and pending action tokens (password reset links) are lost — users simply need to retry. This is inherent to the downtime window and has no lasting effect.

## Limitations

- **IRSA / IAM-based authentication is not supported.** The migration jobs use password-based PostgreSQL authentication (`PGPASSWORD`) and standard Elasticsearch HTTP API. Setups using AWS IAM Roles for Service Accounts (IRSA) with `jdbc:aws-wrapper` or OpenSearch with IAM auth require a custom migration approach.

## Cleanup (post-migration)

After validating the migration, run Phase 5 to automatically remove old Bitnami resources and re-verify:

```bash
source env.sh
bash 5-cleanup-bitnami.sh
```

The script detects and removes old Bitnami StatefulSets (PostgreSQL, Elasticsearch, Keycloak), their associated PVCs, and the migration backup PVC. It then re-verifies that all components remain healthy.

## Design Principles

- **DRY**: Reuses operator-based deploy scripts and manifests — no duplication of operator installation or Helm values
- **Phase-oriented**: 5 clear phases instead of 28 per-component scripts
- **Idempotent**: Each phase can be re-run safely (checks for existing resources before creating)
- **Kubernetes-native**: All data operations run as Kubernetes Jobs inside the cluster
- **Aligned with reference arch**: Deploys the exact same operators and instances as `operator-based/`
- **Validated**: Basic resource checks (CPU, memory, PVC sizes) before deployment
- **Rollback-safe**: Helm values are backed up before cutover, enabling instant rollback

## State Tracking

The scripts maintain migration state in `.state/migration.env` — a plain key-value file that records:
- **Phase completion** (`PHASE_1_COMPLETED=true`, `PHASE_1_TIMESTAMP=...`) — enforces execution order (Phase 3 requires Phase 2, etc.)
- **Deployment decisions** (`ECK_DEPLOYED=true`, `PG_TARGET_IS_EXTERNAL=true`) — tracks what was deployed so subsequent phases know what to validate
- **Logs** — each run appends to `.state/migration-YYYY-MM-DD.log`

Check migration status at any time:

```bash
bash 1-deploy-targets.sh --status
```

The `.state/` directory is local and gitignored. To reset state (e.g. start over), simply delete it:

```bash
rm -rf .state/
```

## Hooks

Each phase supports `pre-` and `post-` hooks for custom logic. Place executable shell scripts in the `hooks/` directory:

| Hook file                    | When it runs                         |
| ---------------------------- | ------------------------------------ |
| `hooks/pre-phase-1.sh`      | Before deploying operators           |
| `hooks/post-phase-1.sh`     | After operators + clusters are ready |
| `hooks/pre-phase-2.sh`      | Before initial backup                |
| `hooks/post-phase-2.sh`     | After initial backup completes       |
| `hooks/pre-phase-3.sh`      | Before cutover (before freeze)       |
| `hooks/post-phase-3.sh`     | After cutover (services restarted)   |
| `hooks/pre-phase-4.sh`      | Before validation                    |
| `hooks/post-phase-4.sh`     | After validation completes           |
| `hooks/pre-phase-5.sh`      | Before Bitnami cleanup               |
| `hooks/post-phase-5.sh`     | After cleanup and re-verification    |
| `hooks/pre-rollback.sh`     | Before rollback                      |
| `hooks/post-rollback.sh`    | After rollback completes             |

Hooks are sourced (not executed), so they have access to all `env.sh` variables and `lib.sh` functions. Only present files are executed — missing hooks are silently skipped.

**Example — DNS switch for Keycloak migration:**

```bash
# hooks/post-phase-3.sh
# Switch the CNAME from old Bitnami Keycloak to new operator Keycloak
log_info "Updating DNS CNAME for Keycloak..."
aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{
        "Name":"keycloak.example.com",
        "Type":"CNAME","TTL":60,
        "ResourceRecords":[{"Value":"keycloak-service.camunda.svc.cluster.local"}]
    }}]}'
```

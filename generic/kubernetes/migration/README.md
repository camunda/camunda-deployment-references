# Camunda Migration: Bitnami → Kubernetes Operators

Migrate a Camunda 8 Helm installation from Bitnami-managed infrastructure (PostgreSQL, Elasticsearch, Keycloak) to Kubernetes operator-managed equivalents (CloudNativePG, ECK, Keycloak Operator).

This migration is designed to align your setup with the [operator-based reference architecture](../operator-based/).

**[Documentation of the migration procedure](https://docs.camunda.io/docs/8.9/self-managed/deployment/helm/operational-tasks/migration-from-bitnami/)** — the official guide is the source of truth for prerequisites, configuration variables, phase descriptions, downtime estimates, precautions, and troubleshooting. This file only covers what is specific to the scripts in this directory.

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

Every variable referenced by these scripts is documented in the [official guide](https://docs.camunda.io/docs/8.9/self-managed/deployment/helm/operational-tasks/migration-from-bitnami/bitnami-to-operators/#key-configuration-variables). Read it before editing `env.sh`.

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
    ├── hooks/                       # Custom pre/post phase hooks
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

## Design Principles

- **DRY**: Reuses operator-based deploy scripts and manifests — no duplication of operator installation or Helm values
- **Phase-oriented**: 5 clear phases instead of 28 per-component scripts
- **Idempotent**: Each phase can be re-run safely (checks for existing resources before creating)
- **Kubernetes-native**: All data operations run as Kubernetes Jobs inside the cluster
- **Aligned with reference arch**: Deploys the exact same operators and instances as `operator-based/`
- **Validated**: Basic resource checks (CPU, memory, PVC sizes) before deployment
- **Rollback-safe**: Helm values are backed up before cutover, enabling instant rollback

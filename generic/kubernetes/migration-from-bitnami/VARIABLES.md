# Environment Variables Reference

This document lists all environment variables used by the migration scripts.

## Global Variables

These variables are set in `0-set-environment.sh` and used across all migrations:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CAMUNDA_NAMESPACE` | Yes | `camunda` | Kubernetes namespace where Camunda is deployed |
| `CAMUNDA_RELEASE_NAME` | Yes | `camunda` | Helm release name of Camunda installation |
| `BACKUP_PVC_NAME` | No | `migration-backup-pvc` | Name of the PVC for backup storage |
| `BACKUP_STORAGE_SIZE` | No | `50Gi` | Size of backup PVC |
| `BACKUP_STORAGE_CLASS` | No | *(default)* | Storage class for backup PVC |

## Orchestration (Elasticsearch → ECK)

### Introspection Variables (auto-detected)

| Variable | Description |
|----------|-------------|
| `ES_STS_NAME` | StatefulSet name of Bitnami Elasticsearch |
| `ES_IMAGE` | Full image path (e.g., `docker.io/bitnami/elasticsearch:8.11.3`) |
| `ES_IMAGE_PULL_SECRETS` | Comma-separated list of imagePullSecrets |
| `ES_REPLICAS` | Number of Elasticsearch replicas |
| `ES_STORAGE_SIZE` | Storage size per node |
| `ES_STORAGE_CLASS` | Storage class name |
| `ES_MEMORY_REQUEST` | Memory request |
| `ES_MEMORY_LIMIT` | Memory limit |
| `ES_CPU_REQUEST` | CPU request |
| `ES_CPU_LIMIT` | CPU limit |

### Target Variables (ECK)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ECK_CLUSTER_NAME` | No | `elasticsearch` | Name of ECK Elasticsearch cluster |
| `ES_VERSION` | No | `8.19.8` | Elasticsearch version |
| `BACKUP_PVC` | No | `migration-backup-pvc` | PVC for backup/restore operations |

### Template Variables (templates/eck-cluster.yml)

```bash
# Required for eck-cluster.yml
export NAMESPACE="camunda"
export ECK_CLUSTER_NAME="elasticsearch"
export ES_VERSION="8.19.8"
export ES_REPLICAS="3"
export ES_STORAGE_SIZE="64Gi"
export ES_MEMORY_REQUEST="2Gi"
export ES_MEMORY_LIMIT="2Gi"
export ES_CPU_REQUEST="1"
export ES_CPU_LIMIT="2"
export BACKUP_PVC="migration-backup-pvc"
```

## Identity (PostgreSQL → CNPG)

### Introspection Variables (auto-detected)

| Variable | Description |
|----------|-------------|
| `PG_STS_NAME` | StatefulSet name of Bitnami PostgreSQL |
| `PG_IMAGE` | Full image path |
| `PG_IMAGE_PULL_SECRETS` | Comma-separated list of imagePullSecrets |
| `PG_VERSION` | PostgreSQL version (e.g., `15.4.0`) |
| `PG_DATABASE` | Database name (default: `identity`) |
| `PG_USERNAME` | Database username |
| `PG_PASSWORD` | Database password (from secret) |
| `PG_REPLICAS` | Number of replicas |
| `PG_STORAGE_SIZE` | Storage size |
| `PG_STORAGE_CLASS` | Storage class name |

### Target Variables (CNPG)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CNPG_CLUSTER_NAME` | No | `pg-identity` | Name of CNPG cluster |
| `TARGET_DB_TYPE` | Auto | `cnpg` or `managed` | Target database type |
| `TARGET_PG_HOST` | Auto | `${CNPG_CLUSTER_NAME}-rw` | Target PostgreSQL host |
| `TARGET_PG_PORT` | No | `5432` | Target PostgreSQL port |

### Template Variables (templates/cnpg-cluster.yml)

```bash
# Required for cnpg-cluster.yml
export NAMESPACE="camunda"
export CNPG_CLUSTER_NAME="pg-identity"
export PG_IMAGE="ghcr.io/cloudnative-pg/postgresql:17.5"
export PG_DATABASE="identity"
export PG_USERNAME="identity"
export PG_REPLICAS="1"
export PG_STORAGE_SIZE="15Gi"
```

### Template Variables (templates/pg-secrets.yml)

```bash
# Required for pg-secrets.yml
export NAMESPACE="camunda"
export CNPG_CLUSTER_NAME="pg-identity"
export PG_USERNAME="identity"
export PG_PASSWORD="<generated>"
export PG_SUPERUSER_PASSWORD="<generated>"
```

## Keycloak (Keycloak + PostgreSQL → Keycloak Operator + CNPG)

### Introspection Variables (auto-detected)

| Variable | Description |
|----------|-------------|
| `KC_STS_NAME` | StatefulSet name of Bitnami Keycloak |
| `KC_IMAGE` | Full Keycloak image path |
| `KC_VERSION` | Keycloak version |
| `KC_REPLICAS` | Number of Keycloak replicas |
| `KC_IMAGE_PULL_SECRETS` | Comma-separated list of imagePullSecrets |
| `KC_ADMIN_USER` | Keycloak admin username |
| `KC_ADMIN_PASSWORD` | Keycloak admin password |
| `KC_HAS_CUSTOM_VOLUMES` | `true` if custom volumes detected |
| `KC_CUSTOM_VOLUMES` | JSON of custom volumes |
| `KC_CUSTOM_MOUNTS` | JSON of custom volume mounts |
| `PG_MODE` | `integrated` or `external` PostgreSQL |
| `KEYCLOAK_DB_NAME` | Database name (default: `keycloak`) |

### Target Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEYCLOAK_CR_NAME` | No | `keycloak` | Name of Keycloak CR |
| `KEYCLOAK_DOMAIN_MODE` | User input | `domain` or `no-domain` | Access mode |
| `CAMUNDA_DOMAIN` | If domain mode | - | Domain for Keycloak access |
| `CNPG_CLUSTER_NAME` | No | `pg-keycloak` | Name of CNPG cluster |

### Template Variables (templates/keycloak-cr-domain.yml)

```bash
# Required for keycloak-cr-domain.yml
export NAMESPACE="camunda"
export KEYCLOAK_CR_NAME="keycloak"
export KC_IMAGE="docker.io/camunda/keycloak:quay-optimized-26.3.2"
export KC_REPLICAS="1"
export CNPG_CLUSTER_NAME="pg-keycloak"
export PG_DATABASE="keycloak"
export CAMUNDA_DOMAIN="camunda.example.com"
```

### Template Variables (templates/keycloak-cr-no-domain.yml)

```bash
# Required for keycloak-cr-no-domain.yml
export NAMESPACE="camunda"
export KEYCLOAK_CR_NAME="keycloak"
export KC_IMAGE="docker.io/camunda/keycloak:quay-optimized-26.3.2"
export KC_REPLICAS="1"
export CNPG_CLUSTER_NAME="pg-keycloak"
export PG_DATABASE="keycloak"
```

### Template Variables (templates/helm-values-keycloak-domain.yml)

```bash
# Required for helm-values-keycloak-domain.yml
export CAMUNDA_DOMAIN="camunda.example.com"
```

## WebModeler (PostgreSQL → CNPG)

### Introspection Variables (auto-detected)

| Variable | Description |
|----------|-------------|
| `WEBMODELER_DEPLOYED` | `true` if WebModeler is deployed |
| `PG_STS_NAME` | StatefulSet name of Bitnami PostgreSQL |
| `PG_IMAGE` | Full image path |
| `PG_DATABASE` | Database name (default: `webmodeler`) |
| `PG_USERNAME` | Database username |
| `PG_PASSWORD` | Database password |
| `PG_STORAGE_SIZE` | Storage size |

### Target Variables (CNPG)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CNPG_CLUSTER_NAME` | No | `pg-webmodeler` | Name of CNPG cluster |
| `TARGET_DB_TYPE` | Auto | `cnpg` or `managed` | Target database type |
| `TARGET_PG_HOST` | Auto | `${CNPG_CLUSTER_NAME}-rw` | Target PostgreSQL host |

### Template Variables (templates/cnpg-cluster.yml)

```bash
# Required for cnpg-cluster.yml
export NAMESPACE="camunda"
export CNPG_CLUSTER_NAME="pg-webmodeler"
export PG_IMAGE="ghcr.io/cloudnative-pg/postgresql:17.5"
export PG_DATABASE="webmodeler"
export PG_USERNAME="webmodeler"
export PG_REPLICAS="1"
export PG_STORAGE_SIZE="15Gi"
```

## Backup Job Variables

### PostgreSQL Backup (templates/backup-job.yml)

```bash
export NAMESPACE="camunda"
export JOB_NAME="backup-identity-$(date +%s)"
export PG_IMAGE="postgres:15"
export PG_HOST="camunda-postgresql"
export PG_PORT="5432"
export PG_DATABASE="identity"
export PG_USERNAME="identity"
export PG_SECRET_NAME="camunda-postgresql"
export PG_SECRET_KEY="password"
export BACKUP_PVC="migration-backup-pvc"
export BACKUP_FILE="identity-backup.dump"
```

### Elasticsearch Backup (templates/es-backup-job.yml)

```bash
export NAMESPACE="camunda"
export JOB_NAME="backup-es-$(date +%s)"
export ES_HOST="camunda-elasticsearch"
export ES_PORT="9200"
export BACKUP_PVC="migration-backup-pvc"
export SNAPSHOT_NAME="migration-backup"
export SNAPSHOT_REPO="migration_repo"
```

## Helm Values Template Variables

### ECK (templates/helm-values-eck.yml)

```bash
export ECK_CLUSTER_NAME="elasticsearch"
```

### CNPG Identity (templates/helm-values-cnpg.yml)

```bash
export CNPG_CLUSTER_NAME="pg-identity"
export PG_DATABASE="identity"
```

### CNPG WebModeler (templates/helm-values-cnpg.yml)

```bash
export CNPG_CLUSTER_NAME="pg-webmodeler"
```

## Secret Naming Convention

All CNPG clusters use consistent secret naming (aligned with `operator-based/` reference):

| Secret | Content | Used By |
|--------|---------|---------|
| `${CNPG_CLUSTER_NAME}-secret` | `username`, `password` | Application credentials |
| `${CNPG_CLUSTER_NAME}-superuser-secret` | `username` (root), `password` | Superuser credentials |

Examples:
- `pg-identity-secret` / `pg-identity-superuser-secret`
- `pg-keycloak-secret` / `pg-keycloak-superuser-secret`
- `pg-webmodeler-secret` / `pg-webmodeler-superuser-secret`

## State Files

Each migration stores state in `.state/` directory:

| File | Description |
|------|-------------|
| `.state/skip` | If present, migration is skipped |
| `.state/${component}.env` | Environment variables from introspection |
| `.state/postgres.env` | PostgreSQL introspection data |
| `.state/cnpg-cluster.yml` | Generated CNPG cluster manifest |
| `.state/pg-secrets.yml` | Generated secrets manifest |
| `.state/helm-values-target.yml` | Generated Helm values |
| `.state/keycloak-operator.yml` | Generated Keycloak CR |

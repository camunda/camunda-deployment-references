# Shared Job Templates

This directory contains reusable Kubernetes Job templates for database migrations.

## Templates

### PostgreSQL

| Template | Description |
|----------|-------------|
| `postgres-backup-job.yml` | Parameterized pg_dump backup job |
| `postgres-restore-job.yml` | Parameterized pg_restore job |

### Elasticsearch

| Template | Description |
|----------|-------------|
| `elasticsearch-backup-job.yml` | Elasticsearch snapshot backup job |
| `elasticsearch-restore-job.yml` | Elasticsearch snapshot restore job |

## Usage

These templates use environment variable substitution with `envsubst`. Set the required environment variables, then apply the template:

```bash
# Example: PostgreSQL backup for Identity
export COMPONENT="identity"
export NAMESPACE="camunda"
export PG_HOST="camunda-postgresql.camunda.svc.cluster.local"
export PG_PORT="5432"
export PG_DATABASE="identity"
export PG_USERNAME="postgres"
export PG_IMAGE="docker.io/bitnami/postgresql:15.6.0-debian-12-r5"
export PG_SECRET_NAME="camunda-postgresql"
export BACKUP_PVC="migration-backup-pvc"
export TIMESTAMP=$(date +%Y%m%d-%H%M%S)

envsubst < postgres-backup-job.yml | kubectl apply -f -
```

## Required Variables

### PostgreSQL Backup

| Variable | Description | Example |
|----------|-------------|---------|
| `COMPONENT` | Component name (identity, keycloak, webmodeler) | `identity` |
| `NAMESPACE` | Kubernetes namespace | `camunda` |
| `PG_HOST` | PostgreSQL host | `camunda-postgresql.camunda.svc.cluster.local` |
| `PG_PORT` | PostgreSQL port | `5432` |
| `PG_DATABASE` | Database name | `identity` |
| `PG_USERNAME` | Database user | `postgres` |
| `PG_IMAGE` | PostgreSQL image (same version as source) | `postgres:15` |
| `PG_SECRET_NAME` | Secret containing `postgres-password` | `camunda-postgresql` |
| `BACKUP_PVC` | PVC for backup storage | `migration-backup-pvc` |
| `TIMESTAMP` | Unique timestamp | `$(date +%Y%m%d-%H%M%S)` |

### PostgreSQL Restore

| Variable | Description | Example |
|----------|-------------|---------|
| `COMPONENT` | Component name | `identity` |
| `NAMESPACE` | Kubernetes namespace | `camunda` |
| `TARGET_PG_HOST` | Target PostgreSQL host | `pg-identity-rw.camunda.svc.cluster.local` |
| `TARGET_PG_PORT` | Target PostgreSQL port | `5432` |
| `TARGET_PG_DATABASE` | Target database name | `identity` |
| `TARGET_PG_USER` | Target database user | `identity` |
| `PG_IMAGE` | PostgreSQL image (compatible version) | `postgres:15` |
| `DB_SECRET_NAME` | Target secret containing `password` | `pg-identity-app` |
| `BACKUP_PVC` | PVC with backup data | `migration-backup-pvc` |
| `BACKUP_FILE` | Specific backup file (optional) | `identity-db-final.dump` |
| `TIMESTAMP` | Unique timestamp | `$(date +%Y%m%d-%H%M%S)` |

### Elasticsearch Backup

| Variable | Description | Example |
|----------|-------------|---------|
| `NAMESPACE` | Kubernetes namespace | `camunda` |
| `ES_HOST` | Source Elasticsearch host | `camunda-elasticsearch.camunda.svc.cluster.local` |
| `ES_PORT` | Elasticsearch port | `9200` |
| `ES_USERNAME` | Elasticsearch user | `elastic` |
| `ES_SECRET_NAME` | Secret containing `elastic` password | `elasticsearch-credentials` |
| `SNAPSHOT_REPO` | Snapshot repository name | `migration_backup` |
| `SNAPSHOT_NAME` | Snapshot name | `pre-migration-$(date +%Y%m%d-%H%M%S)` |
| `TIMESTAMP` | Unique timestamp | `$(date +%Y%m%d-%H%M%S)` |

### Elasticsearch Restore

| Variable | Description | Example |
|----------|-------------|---------|
| `NAMESPACE` | Kubernetes namespace | `camunda` |
| `TARGET_ES_HOST` | Target (ECK) Elasticsearch host | `elasticsearch-es-http.camunda.svc.cluster.local` |
| `TARGET_ES_PORT` | Elasticsearch port | `9200` |
| `ES_USERNAME` | Elasticsearch user | `elastic` |
| `ES_SECRET_NAME` | Target secret containing `elastic` password | `elasticsearch-es-elastic-user` |
| `SNAPSHOT_REPO` | Snapshot repository name | `migration_backup` |
| `SNAPSHOT_NAME` | Snapshot name to restore | `pre-migration-20241216-120000` |
| `TIMESTAMP` | Unique timestamp | `$(date +%Y%m%d-%H%M%S)` |

## Prerequisites

### For PostgreSQL Jobs

1. Create a PVC for backup storage:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: migration-backup-pvc
     namespace: camunda
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 10Gi
   EOF
   ```

### For Elasticsearch Jobs

1. Register a snapshot repository on both source and target:
   ```bash
   curl -X PUT "http://elasticsearch:9200/_snapshot/migration_backup" \
     -H 'Content-Type: application/json' \
     -d '{"type": "fs", "settings": {"location": "/backup/elasticsearch"}}'
   ```

2. Ensure the backup path is accessible (mounted volume, S3, etc.)

## Integration with Migration Scripts

These templates can be referenced from the component migration scripts. For example:

```bash
# In 1-backup.sh
source "${SCRIPT_DIR}/../shared/introspect-postgres.sh"
# ... introspect and set variables ...
envsubst < "${SCRIPT_DIR}/../shared/jobs/postgres-backup-job.yml" | kubectl apply -f -
```

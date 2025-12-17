# Templates Documentation

This directory structure uses `envsubst`-based YAML templates for Kubernetes manifests and Helm values. This approach separates the manifest definitions from the orchestration logic in the shell scripts.

## Structure

Each migration component has a `templates/` directory:

```
migrations/
├── orchestration/
│   └── templates/
│       ├── backup-pvc.yml            # PVC for ES backups
│       ├── es-backup-job.yml         # Elasticsearch backup job
│       ├── eck-cluster.yml           # ECK Elasticsearch CRD (reference-aligned)
│       ├── es-restore-job.yml        # Elasticsearch restore job
│       ├── helm-values-eck.yml       # Helm values for ECK
│       └── helm-values-managed.yml   # Helm values for managed ES
├── identity/
│   └── templates/
│       ├── backup-pvc.yml            # PVC for backups
│       ├── backup-job.yml            # pg_dump job
│       ├── cnpg-cluster.yml          # CNPG PostgreSQL cluster (reference-aligned)
│       ├── pg-secrets.yml            # PostgreSQL secrets (app + superuser)
│       ├── restore-job.yml           # pg_restore job
│       ├── helm-values-cnpg.yml      # Helm values for CNPG
│       └── helm-values-managed.yml   # Helm values for managed PG
├── keycloak/
│   └── templates/
│       ├── backup-pvc.yml            # PVC for backups
│       ├── realm-export-job.yml      # Keycloak realm export
│       ├── pg-backup-job.yml         # pg_dump job
│       ├── cnpg-cluster.yml          # CNPG PostgreSQL cluster (with lock_timeout)
│       ├── pg-secrets.yml            # PostgreSQL secrets (app + superuser)
│       ├── keycloak-cr-domain.yml    # Keycloak CR with NGINX Ingress + TLS
│       ├── keycloak-cr-no-domain.yml # Keycloak CR for local/development
│       ├── pg-restore-job.yml        # pg_restore job
│       ├── helm-values-keycloak-domain.yml    # Helm values with domain
│       └── helm-values-keycloak-no-domain.yml # Helm values without domain
└── webmodeler/
    └── templates/
        ├── backup-pvc.yml            # PVC for backups
        ├── backup-job.yml            # pg_dump job
        ├── cnpg-cluster.yml          # CNPG PostgreSQL cluster
        ├── pg-secrets.yml            # PostgreSQL secrets (app + superuser)
        ├── restore-job.yml           # pg_restore job
        ├── helm-values-cnpg.yml      # Helm values for CNPG
        └── helm-values-managed.yml   # Helm values for managed PG
```

## Usage

Templates use `${VARIABLE}` syntax and are processed with `envsubst`:

```bash
# Set environment variables
export NAMESPACE="camunda"
export BACKUP_PVC="migration-backup"
export BACKUP_STORAGE_SIZE="50Gi"
export STORAGE_CLASS=""

# Generate manifest
envsubst < templates/backup-pvc.yml | kubectl apply -f -

# Or save to state directory for reference
envsubst < templates/backup-job.yml > .state/backup-job.yml
kubectl apply -f .state/backup-job.yml
```

## Required Variables

Each template documents its required environment variables in a header comment:

```yaml
# PostgreSQL Backup Job using pg_dump
# Required env vars:
#   NAMESPACE, JOB_NAME, PG_IMAGE, PG_HOST, PG_PORT
#   PG_DATABASE, PG_USERNAME, PG_SECRET_NAME, PG_SECRET_KEY
#   BACKUP_PVC, BACKUP_FILE
# Usage: envsubst < backup-job.yml | kubectl apply -f -
```

## Template Categories

### Backup Templates
- **backup-pvc.yml** - Persistent Volume Claim for storing backups
- **backup-job.yml / pg-backup-job.yml** - PostgreSQL pg_dump jobs
- **es-backup-job.yml** - Elasticsearch snapshot jobs
- **realm-export-job.yml** - Keycloak realm export jobs

### Infrastructure Templates
- **cnpg-cluster.yml** - CloudNativePG PostgreSQL cluster
- **eck-cluster.yml** - ECK Elasticsearch cluster
- **pg-secrets.yml** - PostgreSQL secrets (app credentials + superuser)
- **keycloak-cr-domain.yml** - Keycloak Operator CR with domain (NGINX Ingress + TLS)
- **keycloak-cr-no-domain.yml** - Keycloak Operator CR without domain (local/development)

### Restore Templates
- **restore-job.yml / pg-restore-job.yml** - PostgreSQL pg_restore jobs
- **es-restore-job.yml** - Elasticsearch snapshot restore jobs

### Helm Values Templates
- **helm-values-cnpg.yml / helm-values-eck.yml** - Values for CNPG/ECK Operator targets
- **helm-values-managed.yml** - Values for managed service targets
- **helm-values-keycloak-domain.yml** - Keycloak values with domain (external access)
- **helm-values-keycloak-no-domain.yml** - Keycloak values without domain (local access)

## Target Types

All migrations support two target types:

### 1. Kubernetes Operators (Recommended)
- **Elasticsearch**: ECK (Elastic Cloud on Kubernetes)
- **PostgreSQL**: CloudNativePG (CNPG)
- **Keycloak**: Keycloak Operator

Benefits: Native Kubernetes integration, CRD-based management, automatic TLS, backup operators

### 2. Managed Services
- **Elasticsearch**: AWS OpenSearch, Elastic Cloud, Azure Elasticsearch
- **PostgreSQL**: AWS RDS, Azure PostgreSQL Flexible Server, GCP Cloud SQL

Benefits: Fully managed, automatic patching, built-in HA, enterprise support

## Keycloak Domain Configuration

Keycloak migration supports two modes based on your network configuration:

### With Domain (Production)
Use `keycloak-cr-domain.yml` and `helm-values-keycloak-domain.yml`:
- NGINX Ingress with TLS termination
- External HTTPS access via `${CAMUNDA_DOMAIN}`
- Proxy headers for proper redirect handling
- Strict hostname validation

```bash
export CAMUNDA_DOMAIN="camunda.example.com"
envsubst < templates/keycloak-cr-domain.yml | kubectl apply -f -
envsubst < templates/helm-values-keycloak-domain.yml > values.yaml
```

### Without Domain (Local/Development)
Use `keycloak-cr-no-domain.yml` and `helm-values-keycloak-no-domain.yml`:
- No Ingress required
- Access via port-forwarding: `kubectl port-forward svc/keycloak-service 18080:8080`
- Token signed with service name hostname
- Non-strict hostname validation

```bash
envsubst < templates/keycloak-cr-no-domain.yml | kubectl apply -f -
envsubst < templates/helm-values-keycloak-no-domain.yml > values.yaml
```

## Reference Alignment

All operator templates are aligned with the reference configurations in:
```
generic/kubernetes/operator-based/
├── elasticsearch/elasticsearch-cluster.yml
├── postgresql/postgresql-clusters.yml
└── keycloak/keycloak-instance-*.yml
```

Key alignment points:
- **ECK**: `node.store.allow_mmap: 'false'`, deprecation logging off, podAntiAffinity
- **CNPG**: `superuserSecret`, `seccompProfile: RuntimeDefault`, `dataChecksums: true`
- **Keycloak**: `apiVersion: k8s.keycloak.org/v2alpha1`, aws-wrapper JDBC URL

## Customization

To customize templates:

1. Copy the template to your working directory
2. Modify as needed
3. Use your custom template in the scripts

Or set additional environment variables and modify the templates to use them.

## Related Documentation

- [Camunda Backup/Restore Guide](https://docs.camunda.io/docs/self-managed/operational-guides/backup-and-restore/backup-and-restore/)
- [ECK Documentation](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [Keycloak Operator](https://www.keycloak.org/operator/installation)

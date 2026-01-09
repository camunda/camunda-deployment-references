# Migration from Bitnami to Kubernetes Operators

This guide provides **modular migration workflows** for Camunda Platform 8 infrastructure services from Bitnami Helm sub-charts to Kubernetes operators.

## Available Migrations

Each application can be migrated **independently**:

| Application | Source (Bitnami) | Target (Operator) | Status |
|-------------|------------------|-------------------|--------|
| **Orchestration** | Bitnami Elasticsearch | ECK (Elastic Cloud on K8s) | Optional |
| **Keycloak** | Bitnami Keycloak + PostgreSQL | Keycloak Operator + CNPG | Optional |
| **Management Identity** | Bitnami PostgreSQL | CloudNativePG | Optional |
| **WebModeler** | Bitnami PostgreSQL | CloudNativePG | Optional |

## Prerequisites

### Required Tools

- `kubectl` configured with cluster access
- `helm` v3.x
- `jq` for JSON processing

### Cluster Requirements

- Kubernetes >= 1.24
- Sufficient resources for dual-stack operation (temporary 2x capacity)
- Existing Camunda Platform 8.9+ installation with Bitnami sub-charts

## Quick Start

### Step 1: Configure Base Environment

```bash
# Copy and edit the environment configuration
cp 0-set-environment.sh 0-set-environment.local.sh
vim 0-set-environment.local.sh

# Source the environment
source 0-set-environment.local.sh
```

### Step 2: Run Prerequisites Check

```bash
./1-prerequisites/check-prerequisites.sh
```

### Step 3: Choose Which Application to Migrate

Navigate to the specific application directory and follow its README:

| Application | Directory | Documentation |
|-------------|-----------|---------------|
| Orchestration (Elasticsearch → ECK) | `migrations/orchestration/` | [README](migrations/orchestration/README.md) |
| Keycloak (Bitnami → Keycloak Operator + CNPG) | `migrations/keycloak/` | [README](migrations/keycloak/README.md) |
| Management Identity (PostgreSQL → CNPG) | `migrations/identity/` | [README](migrations/identity/README.md) |
| WebModeler (PostgreSQL → CNPG) | `migrations/webmodeler/` | [README](migrations/webmodeler/README.md) |

## Migration Order Recommendation

For a full migration, we recommend this order:

1. **Orchestration** (Elasticsearch) - Independent, can migrate first
2. **Keycloak** - Includes PostgreSQL, impacts authentication
3. **Management Identity** - PostgreSQL only
4. **WebModeler** - PostgreSQL only, usually can tolerate downtime

> **Note**: Each migration is independent. You can migrate only the components you need.

## Key Features

### Automatic Introspection

Each migration script automatically detects:
- **Image**: Full image path including registry and tag (e.g., `my-registry.io/bitnami/postgresql:15.4.0`)
- **ImagePullSecrets**: Reuses existing secrets for private registries
- **Storage**: Storage class and volume size
- **Configuration**: Existing resource limits, environment variables, etc.

### Private Registry Support

The introspection ensures compatibility with private registries:
- Detects full image path from running pods
- Copies imagePullSecrets to new resources
- Works with air-gapped environments

### Cleanup Commands

Each migration ends with echo commands showing how to clean up Bitnami resources.
These are displayed as echo only - you decide when to run them.

## Directory Structure

```
migration-from-bitnami/
├── 0-set-environment.sh              # Base environment configuration
├── README.md                         # This file
│
├── 1-prerequisites/
│   ├── check-prerequisites.sh        # Validate cluster and tools
│   └── create-backup-pvc.sh          # Create PVC for backup storage
│
├── 2-deploy-operators/
│   ├── deploy-cnpg.sh                # Deploy CloudNativePG operator
│   ├── deploy-eck.sh                 # Deploy ECK operator
│   └── deploy-keycloak-operator.sh   # Deploy Keycloak operator
│
├── migrations/
│   ├── orchestration/                # Elasticsearch → ECK
│   ├── keycloak/                     # Keycloak + PostgreSQL → Operator + CNPG
│   ├── identity/                     # Identity PostgreSQL → CNPG
│   └── webmodeler/                   # WebModeler PostgreSQL → CNPG
│
└── shared/
    ├── introspect-postgres.sh        # Common PostgreSQL introspection
    ├── introspect-elasticsearch.sh   # Common Elasticsearch introspection
    └── jobs/                         # Kubernetes Job templates
```

## Estimated Downtime Per Component

| Component | Data Size | Estimated Downtime |
|-----------|-----------|-------------------|
| PostgreSQL (small) | < 1GB | 5-10 minutes |
| PostgreSQL (medium) | 1-10GB | 15-30 minutes |
| PostgreSQL (large) | > 10GB | 30-60+ minutes |
| Elasticsearch (small) | < 10GB | 10-15 minutes |
| Elasticsearch (medium) | 10-50GB | 20-45 minutes |
| Elasticsearch (large) | > 50GB | 60+ minutes |

## Security Considerations

- Backup PVCs contain sensitive data - ensure proper access controls
- The introspection scripts detect and reuse existing imagePullSecrets
- Secrets are automatically migrated - verify no plaintext exposure
- Consider encrypting backup data at rest
- Remove backup data promptly after successful migration

## CI/CD Integration

This migration is automatically tested via GitHub Actions:

| Workflow | Schedule | Description |
|----------|----------|-------------|
| [Migration from Bitnami Test](../../.github/workflows/generic_kubernetes_migration_from_bitnami_test.yml) | Tuesdays 3 AM | Full migration test on EKS |

### Running Tests Manually

```bash
# Trigger via GitHub CLI
gh workflow run generic_kubernetes_migration_from_bitnami_test.yml \
    --ref main \
    -f enable_tests=true \
    -f delete_clusters=true
```

### Test Configuration

See [test_matrix.yml](../../.github/workflows-config/generic-kubernetes-migration-from-bitnami/test_matrix.yml) for matrix configuration.

## Environment Variables Reference

See [VARIABLES.md](VARIABLES.md) for complete documentation of all environment variables used by migration scripts.

## Reference Architecture Alignment

Templates are aligned with the [operator-based reference architecture](../operator-based/):

| Component | Reference File | Description |
|-----------|---------------|-------------|
| ECK | `elasticsearch/elasticsearch-cluster.yml` | Elasticsearch cluster with anti-affinity |
| CNPG | `postgresql/postgresql-clusters.yml` | PostgreSQL with superuserSecret |
| Keycloak | `keycloak/keycloak-instance-*.yml` | Domain and no-domain modes |

## Troubleshooting

### Common Issues

1. **CNPG cluster stuck in "Creating primary"**
   - Check secrets exist: `kubectl get secret ${CNPG_CLUSTER_NAME}-secret`
   - Verify storage class: `kubectl get sc`

2. **ECK cluster not becoming green**
   - Check pod logs: `kubectl logs -l elasticsearch.k8s.elastic.co/cluster-name=${ECK_CLUSTER_NAME}`
   - Verify memory limits are sufficient

3. **Keycloak Operator not starting**
   - Check CRD is installed: `kubectl get crd keycloaks.k8s.keycloak.org`
   - Verify database connection in `keycloak-operator.yml`

### Getting Help

- [Camunda Backup/Restore Documentation](https://docs.camunda.io/docs/self-managed/operational-guides/backup-restore/)
- [ECK Documentation](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [Keycloak Operator](https://www.keycloak.org/operator/installation)

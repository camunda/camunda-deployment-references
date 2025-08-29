# Camunda Infrastructure with Kubernetes Operators

This guide documents the installation of Camunda infrastructure components using Kubernetes operators. All required files are provided in this directory for easy deployment.

## Prerequisites

- Kubernetes cluster with admin privileges
- `kubectl` configured to access your cluster
- OpenSSL for generating random passwords
- ClusterAdmin privileges (required for operators installation)

<!-- TODO: add a link that explains what an operator is -->

## Quick Start

To deploy all components at once:

```bash
./deploy-all.sh [namespace]
```

Default namespace is `camunda` if not specified.

## Complete Verification

To verify all components at once:

```bash
./verify-all.sh [namespace]
```

This script runs all individual verification scripts and provides a comprehensive status report.

## Infrastructure Components

This deployment includes the following infrastructure components:
- **PostgreSQL**: Three instances for Keycloak, Camunda Identity, and Web Modeler
- **Elasticsearch**: For storing Zeebe and Camunda data (orchestration cluster)
- **Keycloak**: For authentication and identity management

Components are deployed in dependency order: PostgreSQL → Elasticsearch → Keycloak

## Manual Step-by-Step Installation

If you prefer to install components individually:

### 1. PostgreSQL Installation

PostgreSQL uses CloudNativePG, a CNCF component under Apache 2.0 license.

**Files:**
- `01-postgresql-install-operator.sh` - Installs the CloudNativePG operator
- `01-postgresql-create-secrets.sh` - Creates authentication secrets
- `01-postgresql-clusters.yml` - PostgreSQL cluster definitions
- `01-postgresql-wait-ready.sh` - Waits for clusters to become healthy

**Commands:**
```bash
# Install operator
./01-postgresql-install-operator.sh

# Create secrets (generates random passwords)
./01-postgresql-create-secrets.sh camunda

# Deploy clusters
kubectl apply -n camunda -f 01-postgresql-clusters.yml

# Wait for readiness
./01-postgresql-wait-ready.sh camunda
```

**Verification:**
```bash
./01-postgresql-verify.sh camunda
```

**Quick status check:**
```bash
kubectl get clusters -n camunda
kubectl get svc -n camunda | grep "pg-"
```

The deployment creates three PostgreSQL clusters:
- `pg-identity` - For Camunda Identity
- `pg-keycloak` - For Keycloak
- `pg-webmodeler` - For Web Modeler

### 2. Elasticsearch Installation

Elasticsearch uses ECK (Elastic Cloud on Kubernetes), the official operator from Elastic.

**Files:**
- `02-elasticsearch-install-operator.sh` - Installs the ECK operator
- `02-elasticsearch-cluster.yml` - Elasticsearch cluster definition
- `02-elasticsearch-wait-ready.sh` - Waits for cluster to become ready

**Commands:**
```bash
# Install operator
./02-elasticsearch-install-operator.sh

# Deploy cluster
kubectl apply -n camunda -f 02-elasticsearch-cluster.yml

# Wait for readiness
./02-elasticsearch-wait-ready.sh camunda
```

**Verification:**
```bash
./02-elasticsearch-verify.sh camunda
```

**Quick status check:**
```bash
kubectl get elasticsearch -n camunda
kubectl get svc -n camunda | grep "elasticsearch"
```

The deployment creates a 3-node Elasticsearch cluster with:
- Version 8.18.0
- 3 master nodes with anti-affinity
- 64Gi storage per node
- Bounded CPU/memory resources

### 3. Keycloak Installation

Keycloak uses the official Keycloak Operator under Apache 2.0 license.

**Files:**
- `03-keycloak-install-operator.sh` - Installs the Keycloak operator
- `03-keycloak-instance.yml` - Keycloak instance definition
- `03-keycloak-wait-ready.sh` - Waits for instance to become ready
- `03-keycloak-get-admin-credentials.sh` - Retrieves admin credentials

**Commands:**
```bash
# Install operator
./03-keycloak-install-operator.sh camunda

# Deploy instance
kubectl apply -n camunda -f 03-keycloak-instance.yml

# Wait for readiness
./03-keycloak-wait-ready.sh camunda

# Get admin credentials
./03-keycloak-get-admin-credentials.sh camunda
```

**Verification:**
```bash
./03-keycloak-verify.sh camunda
```

**Quick status check:**
```bash
kubectl get keycloak -n camunda
kubectl get svc -n camunda | grep keycloak
```

**Access Keycloak:**
```bash
# Port-forward to access admin console
kubectl -n camunda port-forward svc/keycloak 8080:8080

# Then open: http://localhost:8080/admin/
```

## Configuration Details

### PostgreSQL Configuration

Three separate PostgreSQL clusters are created:
- **pg-identity**: Database `identity`, user `identity`
- **pg-keycloak**: Database `keycloak`, user `keycloak`
- **pg-webmodeler**: Database `webmodeler`, user `webmodeler`

Each cluster includes:
- 1 instance (can be scaled)
- 15Gi storage
- Superuser and application user secrets
- Data checksums enabled

### Elasticsearch Configuration

Single cluster with:
- 3 master nodes for high availability
- Pod anti-affinity for distribution
- TLS disabled for simplicity
- Deprecation warnings disabled
- Read-only root filesystem
- 64Gi persistent storage per node

### Keycloak Configuration

Single instance with:
- PostgreSQL backend (pg-keycloak cluster)
- HTTP enabled (no TLS for simplicity)
- Hostname: localhost (change for production)
- Resource limits: 500m CPU, 1Gi memory

## Connection Information

### PostgreSQL Services

Access via Kubernetes services:
```
pg-identity-rw    - Read/write endpoint
pg-identity-ro    - Read-only endpoint
pg-identity-r     - Any replica endpoint

pg-keycloak-rw    - Read/write endpoint
pg-keycloak-ro    - Read-only endpoint
pg-keycloak-r     - Any replica endpoint

pg-webmodeler-rw  - Read/write endpoint
pg-webmodeler-ro  - Read-only endpoint
pg-webmodeler-r   - Any replica endpoint
```

Credentials stored in secrets:
- `pg-identity-secret` (username: identity)
- `pg-keycloak-secret` (username: keycloak)
- `pg-webmodeler-secret` (username: webmodeler)

### Elasticsearch Services

Access via:
```
elasticsearch-es-http - Main HTTP endpoint (port 9200)
elasticsearch-es-transport - Transport endpoint (port 9300)
```

Credentials in secret: `elasticsearch-es-elastic-user` (username: elastic)

### Keycloak Services

Access via:
```
keycloak - HTTP endpoint (port 8080)
```

Admin credentials in secret: `keycloak-initial-admin`

## Next Steps

After infrastructure deployment:

1. **Configure Keycloak realm** for Camunda
2. **Install Camunda Helm chart** with operator-based infrastructure
3. **Configure monitoring** (Prometheus, Grafana)
4. **Set up TLS** for production deployments

## Troubleshooting

**Check operator status:**
```bash
kubectl get pods -n cnpg-system      # PostgreSQL operator
kubectl get pods -n elastic-system   # Elasticsearch operator
kubectl get pods -n camunda         # Keycloak operator
```

**Check resource status:**
```bash
kubectl get clusters -n camunda      # PostgreSQL clusters
kubectl get elasticsearch -n camunda # Elasticsearch cluster
kubectl get keycloak -n camunda     # Keycloak instance
```

**View logs:**
```bash
kubectl logs -f deployment/cnpg-controller-manager -n cnpg-system
kubectl logs -f statefulset/elastic-operator -n elastic-system
kubectl logs -f deployment/keycloak-operator -n camunda
```

## Cleanup

To remove all components:
```bash
kubectl delete namespace camunda
kubectl delete namespace cnpg-system
kubectl delete namespace elastic-system
```

**Note:** This will delete all data. For production, ensure proper backup procedures.

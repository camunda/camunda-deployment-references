# Camunda Infrastructure with Kubernetes Operators

This guide documents the installation of Camunda infrastructure components using Kubernetes operators. All required files are provided in this directory for easy deployment.

## Prerequisites

- `kubectl` configured to access your cluster
- OpenSSL for generating random passwords
- ClusterAdmin privileges (required to install operators)
- Permission to create the operator namespaces (default: `cnpg-system` and `elastic-system`). Using a dedicated namespace for each operator controller is standard practice. Optionally, you can deploy the operators into the same namespace as Camunda (for example, `camunda`) by specifying that namespace during installation (e.g., using `-n camunda` in your kubectl commands or install scripts/manifests).
- `envsubst` command (part of `gettext` package) for environment variable substitution in manifests

<!-- TODO: add a link that explains what an operator is -->

## Quick Start

These operators run on both Kubernetes and OpenShift; however, we recommend reviewing each operator's documentation to ensure all prerequisites are met.

**Set environment variables first:**
```bash
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_PROTOCOL="http"
```

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

This deployment includes the following infrastructure components:
- PostgreSQL: Three instances for Keycloak, Camunda Identity, and Web Modeler
- Elasticsearch: For storing Zeebe and Camunda data (orchestration cluster)
- Keycloak: For authentication and identity management

Components are deployed in dependency order: PostgreSQL → Elasticsearch → Keycloak

Note: None of these components is mandatory. If you already use a managed service (e.g., managed PostgreSQL, Elasticsearch, or Keycloak), you can skip deploying that component and configure your installation to use the managed service instead.

## Manual Step-by-Step Installation

If you prefer to install components individually:

### 1. PostgreSQL Installation

PostgreSQL uses [CloudNativePG, a CNCF component under Apache 2.0 license](https://landscape.cncf.io/?item=app-definition-and-development--database--cloudnativepg).

- To learn the prerequisites for this installation, refer to the project documentation: https://cloudnative-pg.io/documentation/current/supported_releases/.

- This is an excerpt from https://cloudnative-pg.io/documentation/current/quickstart/#part-2-install-cloudnativepg

This setup provisions three PostgreSQL clusters—one each for Keycloak, Camunda Identity, and Web Modeler.
All clusters target PostgreSQL 15, selected as the common denominator across current Camunda components:
https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements

**Files:**
- `01-postgresql-install-operator.sh` - Installs the CloudNativePG operator
- `01-postgresql-create-secrets.sh` - Creates authentication secrets to access the databases
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

Note: You can also install and configure the CloudNativePG operator using the official Helm chart. To integrate its deployment alongside the Camunda Helm chart, see: https://github.com/cloudnative-pg/charts

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

All configuration options for the PostgreSQL cluster are available in the official CloudNativePG documentation (https://cloudnative-pg.io/documentation/current/cloudnative-pg.v1/)

For monitoring, follow https://cloudnative-pg.io/documentation/current/quickstart/#part-4-monitor-clusters-with-promet

The PostgreSQL cluster installation is now complete; configuration in the chart will be covered in the Camunda installation chapter.

### 2. Elasticsearch Installation

Elasticsearch uses ECK (Elastic Cloud on Kubernetes), the official operator from Elastic under the Elastic license (https://www.elastic.co/licensing/elastic-license).

To learn the prerequisites for this installation, refer to the official documentation https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/deploy-an-orchestrator. This operator works on Kubernetes and OpenShift (https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s#k8s-supported).

- The target version of Elasticsearch, we take the common denominator for the current version of Camunda: https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements, i.e. Elasticsearch 8.16+

- This is an excerpt from https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-yaml-manifest-quickstart

**Files:**
- `02-elasticsearch-install-operator.sh` - Installs the ECK operator
- `02-elasticsearch-cluster.yml` - Elasticsearch cluster 8.18.0 highly available cluster with 3 master nodes, persistent storage, and bounded resources.
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

If you want to integrate the deployment of this operator alongside the Camunda chart, we recommend using: https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-helm-chart


**Verification:**
```bash
./02-elasticsearch-verify.sh camunda
```

**Quick status check:**
```bash
kubectl get elasticsearch -n camunda
kubectl get svc -n camunda | grep "elasticsearch"
```

All configuration options for the Elasticsearch cluster are available in the official ECK documentation (https://www.elastic.co/guide/en/cloud-on-k8s/1.0/k8s-elasticsearch-k8s-elastic-co-v1.html)

### 3. Keycloak Installation

Keycloak uses the official [Keycloak Operator under Apache 2.0 license](https://landscape.cncf.io/?item=provisioning--security-compliance--keycloak).

This is an excerpt from https://www.keycloak.org/operator/installation#_installing_by_using_kubectl_without_operator_lifecycle_manager

- To learn the prerequisites for this installation, see the official Keycloak Operator documentation: https://www.keycloak.org/guides#operator. This operator works on Kubernetes and OpenShift.
- The target Keycloak version, we take the common denominator for the current version of Camunda: https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements, i.e. Keycloak 26+.
- This operator is installed in the same namespace as the Camunda components.
- Keycloak is configured to serve under the path prefix `/auth` and can be accessed via port-forward for administration.

#### Environment Variables

The following environment variables are required for Keycloak realm configuration:

- `CAMUNDA_DOMAIN` - The domain where Camunda will be deployed (default: `localhost`)
- `CAMUNDA_PROTOCOL` - The protocol to use for Camunda URLs (default: `http`)

Example:
```bash
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_PROTOCOL="http"
```

For production deployments, use your actual domain and HTTPS:
```bash
export CAMUNDA_DOMAIN="camunda.example.com"
export CAMUNDA_PROTOCOL="https"
```

**Files:**
- `03-keycloak-install-operator.sh` - Installs the Keycloak operator
- `03-keycloak-instance.yml` - Keycloak instance using CNPG (secret `keycloak-db`), configured to serve under `/auth`
- `03-keycloak-wait-ready.sh` - Waits for instance to become ready
- `03-keycloak-get-admin-credentials.sh` - Retrieves admin credentials to access the Keycloak admin console

**Commands:**
```bash
# Set environment variables
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_PROTOCOL="http"

# Install operator
./03-keycloak-install-operator.sh camunda

# Deploy instance and ingress (with environment variable substitution)
./03-keycloak-deploy.sh camunda

# Wait for readiness
./03-keycloak-wait-ready.sh camunda

# Get admin credentials
./03-keycloak-get-admin-credentials.sh camunda
```

**Verification:**
```bash
./03-keycloak-verify.sh camunda
```

All configuration options for the Keycloak cluster are available in the official documentation (https://www.keycloak.org/operator/advanced-configuration).

As time of now, no helm chart is planned to be integrated by the keycloak team https://github.com/keycloak/keycloak/issues/16210#issuecomment-1462203645.

**Quick status check:**
```bash
kubectl get keycloak -n camunda
kubectl get svc -n camunda | grep keycloak
```

**Access Keycloak:**
- With Ingress on the same domain:
  - Admin console: ${CAMUNDA_PROTOCOL}://${CAMUNDA_DOMAIN}/auth/admin/
- Without Ingress/hostname:
  - Port-forward locally, then open http://localhost:8080/auth/admin/
  ```bash
  kubectl -n camunda port-forward svc/keycloak 8080:8080
  ```

Best practice: change the admin password after the first login.

#### Realm for Camunda

The Keycloak realm for Camunda Platform will be automatically configured by the Camunda Helm chart during installation.

## Next Steps

After infrastructure deployment:

2. **Install Camunda Helm chart** with operator-based infrastructure
3. **Configure monitoring** (Prometheus, Grafana)
4. **Set up TLS** for production deployments

## Cleanup

To remove all components:
```bash
kubectl delete namespace camunda
kubectl delete namespace cnpg-system
kubectl delete namespace elastic-system
```

**Note:** This will delete all data. For production, ensure proper backup procedures.



<!-- TODO: handle images used by the operators (SBOM) -->

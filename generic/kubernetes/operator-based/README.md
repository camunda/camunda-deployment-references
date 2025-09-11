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
# Option 1: Use the provided script (recommended)
source ./0-set-environment.sh

# Option 2: Set variables manually
export CAMUNDA_NAMESPACE="camunda"
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_PROTOCOL="http"
```

To deploy infrastructure components:

```bash
./deploy-all-reqs.sh [namespace]
```

Default namespace is `camunda` if not specified. This deploys PostgreSQL, Elasticsearch, and Keycloak operators and instances.

To deploy Camunda Platform after infrastructure:

```bash
# Create Identity secrets first
./04-camunda-create-identity-secret.sh

# Deploy Camunda Platform
./04-camunda-deploy.sh [namespace]
```

## Complete Verification

To verify all components at once:

```bash
./verify-all-reqs.sh [namespace]
```

This script runs all individual verification scripts for infrastructure components and provides a comprehensive status report.

This deployment includes the following components:
- **Infrastructure** (managed by operators):
  - PostgreSQL: Three instances for Keycloak, Camunda Identity, and Web Modeler
  - Elasticsearch: For storing Zeebe and Camunda data (orchestration cluster) with authentication enabled
  - Keycloak: For authentication and identity management
- **Camunda Platform 8**: Complete installation using the official Helm chart

Components are deployed in dependency order: PostgreSQL → Elasticsearch → Keycloak

**Infrastructure Deployment:**
- `./deploy-all-reqs.sh` - Deploy infrastructure components (PostgreSQL, Elasticsearch, Keycloak)
- Use `--skip-postgresql`, `--skip-elasticsearch`, or `--skip-keycloak` to skip specific components

**Camunda Platform Deployment:**
- `./04-camunda-deploy.sh` - Deploy Camunda Platform using the infrastructure above

Note: Infrastructure components are optional. If you already use managed services (e.g., managed PostgreSQL, Elasticsearch, or Keycloak), you can skip deploying those components and configure Camunda to use the managed services instead.

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
- `02-elasticsearch-cluster.yml` - Elasticsearch cluster 8.18.0 with authentication enabled, 3 master nodes, persistent storage, and bounded resources
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

#### Elasticsearch Authentication

The ECK operator automatically creates authentication credentials for Elasticsearch:

**Accessing Elasticsearch credentials:**
```bash
# Get the automatically generated password for the 'elastic' user
kubectl get secret elasticsearch-es-elastic-user -n camunda -o go-template='{{.data.elastic | base64decode}}'

# The username is always 'elastic'
# The Elasticsearch URL is: https://elasticsearch-es-http:9200 (HTTPS with TLS enabled)
```

**How it works in Camunda configuration:**
The `values-operator-based.yml` file configures Camunda to use these ECK-generated credentials:
```yaml
global:
  elasticsearch:
    auth:
      username: elastic
      existingSecret: elasticsearch-es-elastic-user  # Auto-created by ECK
      existingSecretKey: elastic                     # Password key in the secret
    tls:
      enabled: true  # ECK auto-generates TLS certificates
```

The ECK operator handles all security aspects:
- 🔒 **Auto-generated TLS certificates** for HTTPS communication
- 🎟️ **Auto-generated elastic user password** stored in Kubernetes secrets
- 🛡️ **Secure by default** - no manual certificate or password management needed

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

#### Configure a Realm for Camunda

The Keycloak realm for Camunda Platform will be automatically configured by the Camunda Helm chart during installation.

### 4. Camunda Platform Installation

After deploying the infrastructure (PostgreSQL, Elasticsearch, and Keycloak), you can deploy the complete Camunda Platform 8.

**Files:**
- `04-camunda-deploy.sh` - Deploys Camunda Platform using Helm with operator-based infrastructure
- `04-camunda-create-identity-secret.sh` - Creates Kubernetes secret with Identity component credentials
- `04-camunda-wait-ready.sh` - Waits for all Camunda components to be ready
- `04-camunda-verify.sh` - Verifies Camunda Platform deployment
- `values-operator-based.yml` - Helm values configured for operator-based infrastructure

**Commands:**
```bash
# Set environment variables
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_PROTOCOL="http"
export CAMUNDA_NAMESPACE="camunda"

# Create Identity component secrets
./04-camunda-create-identity-secret.sh

# Deploy Camunda Platform
./04-camunda-deploy.sh camunda

# Wait for readiness
./04-camunda-wait-ready.sh camunda

# Verify deployment
./04-camunda-verify.sh camunda
```

**Alternative: Use the deployment script**
```bash
# Deploy infrastructure first
./deploy-all-reqs.sh camunda

# Create Identity secrets
./04-camunda-create-identity-secret.sh

# Then deploy Camunda Platform
./04-camunda-deploy.sh camunda
```

#### Identity Secrets

The `04-camunda-create-identity-secret.sh` script generates secure random tokens for Camunda Identity components and creates a Kubernetes secret named `camunda-credentials` containing:

- `identity-connectors-client-token` - Authentication token for Connectors
- `identity-console-client-token` - Authentication token for Console
- `identity-optimize-client-token` - Authentication token for Optimize
- `identity-orchestration-client-token` - Authentication token for Orchestration (Zeebe)
- `identity-admin-client-token` - Admin authentication token
- `identity-firstuser-password` - Password for the first user account
- `smtp-password` - SMTP password (empty by default)

**Important:** Save the generated credentials in a secure location for future reference.

The Camunda Platform deployment includes:
- **Identity**: Authentication and user management
- **Operate**: Process monitoring and management
- **Optimize**: Process analytics and optimization
- **Tasklist**: Human task management
- **Zeebe**: Process orchestration engine
- **Connectors**: External system integrations
- **WebModeler**: Visual process modeling (optional)
- **Console**: Admin interface (optional)

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

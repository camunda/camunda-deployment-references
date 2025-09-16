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
```

To deploy infrastructure components individually:

```bash

# Deploy Elasticsearch
cd elasticsearch && ./deploy.sh

# Deploy PostgreSQL
cd postgresql && ./deploy.sh

# Deploy Keycloak
cd keycloak && ./deploy.sh
```

To deploy Camunda Platform after infrastructure:

```bash
# Create Identity secrets first
./tests/utils/generate-identity-secrets.sh

# Deploy Camunda Platform using the values files
# (Manual deployment using kubectl and the provided values files)
```

## Complete Verification

To verify individual components:

```bash
# Verify PostgreSQL
kubectl get clusters -n camunda
kubectl get svc -n camunda | grep "pg-"

# Verify Elasticsearch
kubectl get elasticsearch -n camunda
kubectl get svc -n camunda | grep "elasticsearch"

# Verify Keycloak
kubectl get keycloak -n camunda
kubectl get svc -n camunda | grep keycloak
```

This deployment includes the following components:
- **Infrastructure** (managed by operators):
  - PostgreSQL: Three instances for Keycloak, Camunda Identity, and Web Modeler
  - Elasticsearch: For storing Zeebe and Camunda data (orchestration cluster) with authentication enabled
  - Keycloak: For authentication and identity management
- **Camunda Platform 8**: Complete installation using the official Helm chart

Components are deployed in dependency order: PostgreSQL → Elasticsearch → Keycloak

**Infrastructure Deployment:**
- `postgresql/deploy.sh` - Deploy PostgreSQL via CloudNativePG operator
- `elasticsearch/deploy.sh` - Deploy Elasticsearch via ECK operator
- `keycloak/deploy.sh` - Deploy Keycloak via Keycloak operator

**Camunda Platform Deployment:**
- Use the provided Helm values files in each component directory to configure Camunda Platform with the operator-based infrastructure

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
- `postgresql/deploy.sh` - Installs the CloudNativePG operator and deploys PostgreSQL clusters
- `postgresql/set-secrets.sh` - Creates authentication secrets to access the databases
- `postgresql/postgresql-clusters.yml` - PostgreSQL cluster definitions
- `postgresql/deploy-openshift.sh` - OpenShift-specific deployment script
- `postgresql/camunda-identity-values.yml` - Camunda Identity Helm values for PostgreSQL
- `postgresql/camunda-webmodeler-values.yml` - Camunda Web Modeler Helm values for PostgreSQL

**Commands:**
```bash
# Deploy PostgreSQL (includes operator installation, secrets creation, and cluster deployment)
cd postgresql && ./deploy.sh

# For OpenShift
cd postgresql && ./deploy-openshift.sh
```

Note: You can also install and configure the CloudNativePG operator using the official Helm chart. To integrate its deployment alongside the Camunda Helm chart, see: https://github.com/cloudnative-pg/charts

**Verification:**
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
- `elasticsearch/deploy.sh` - Installs the ECK operator and deploys Elasticsearch cluster
- `elasticsearch/elasticsearch-cluster.yml` - Elasticsearch cluster 8.18.0 with authentication enabled, 3 master nodes, persistent storage, and bounded resources
- `elasticsearch/camunda-values.yml` - Camunda Helm values for Elasticsearch configuration

**Commands:**
```bash
# Deploy Elasticsearch (includes operator installation and cluster deployment)
cd elasticsearch && ./deploy.sh
```

If you want to integrate the deployment of this operator alongside the Camunda chart, we recommend using: https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-helm-chart


**Verification:**
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
The `values-all-components.yml` file configures Camunda to use these ECK-generated credentials:
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
- `keycloak/deploy.sh` - Installs the Keycloak operator and deploys Keycloak instance
- `keycloak/keycloak-instance-no-domain.yml` - Keycloak instance without domain configuration
- `keycloak/keycloak-instance-domain-nginx.yml` - Keycloak instance with Nginx ingress configuration
- `keycloak/keycloak-instance-domain-openshift.yml` - Keycloak instance with OpenShift route configuration
- `keycloak/camunda-keycloak-domain-values.yml` - Camunda Helm values for Keycloak with domain
- `keycloak/camunda-keycloak-no-domain-values.yml.yml` - Camunda Helm values for Keycloak without domain

**Commands:**
```bash
# Set environment variables
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_NAMESPACE="camunda"

# Deploy Keycloak (includes operator installation and instance deployment)
cd keycloak && ./deploy.sh
```

**Verification:**
```bash
kubectl get keycloak -n camunda
kubectl get svc -n camunda | grep keycloak
```

**Access Keycloak:**
- With Ingress on the same domain:
  - Admin console: ${CAMUNDA_DOMAIN}/auth/admin/
- Without Ingress/hostname:
  - Port-forward locally, then open http://localhost:8080/auth/admin/
  ```bash
  kubectl -n camunda port-forward svc/keycloak 8080:8080
  ```

**Get admin credentials:**
```bash
# Get admin username
kubectl get secret keycloak-initial-admin -n camunda -o jsonpath='{.data.username}' | base64 -d

# Get admin password
kubectl get secret keycloak-initial-admin -n camunda -o jsonpath='{.data.password}' | base64 -d
```

Best practice: change the admin password after the first login.

#### Configure a Realm for Camunda

The Keycloak realm for Camunda Platform will be automatically configured by the Camunda Helm chart during installation.

### 4. Camunda Platform Installation

After deploying the infrastructure (PostgreSQL, Elasticsearch, and Keycloak), you can deploy the complete Camunda Platform 8.

**Files:**
- `tests/utils/generate-identity-secrets.sh` - Creates Kubernetes secret with Identity component credentials
- `tests/utils/camunda-base-values.yml` - Base Camunda Helm values
- `tests/utils/camunda-domain-values.yml` - Camunda Helm values with domain configuration
- `tests/utils/camunda-values-identity-secrets.yml` - Camunda Helm values for Identity secrets
- Component-specific values files in `postgresql/`, `elasticsearch/`, and `keycloak/` directories

**Commands:**
```bash
# Set environment variables
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_NAMESPACE="camunda"

# Create Identity component secrets
./tests/utils/generate-identity-secrets.sh

# Deploy Camunda Platform using Helm with the appropriate values files
# Combine values from multiple files for complete configuration
helm install camunda camunda/camunda-platform \
  -n camunda \
  -f tests/utils/camunda-base-values.yml \
  -f tests/utils/camunda-domain-values.yml \
  -f tests/utils/camunda-values-identity-secrets.yml \
  -f postgresql/camunda-identity-values.yml \
  -f postgresql/camunda-webmodeler-values.yml \
  -f elasticsearch/camunda-values.yml \
  -f keycloak/camunda-keycloak-no-domain-values.yml.yml
```

**Alternative: Use individual deployment scripts**
```bash
# Deploy infrastructure components individually
cd postgresql && ./deploy.sh
cd ../elasticsearch && ./deploy.sh
cd ../keycloak && ./deploy.sh

# Create Identity secrets
./tests/utils/generate-identity-secrets.sh

# Then deploy Camunda Platform with Helm using the values files
```

#### Identity Secrets

The `tests/utils/generate-identity-secrets.sh` script generates secure random tokens for Camunda Identity components and creates a Kubernetes secret named `camunda-credentials` containing:

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

## Additional Scripts and Utilities

This deployment includes several additional utility scripts:

**Setup and Environment:**
- `0-set-environment.sh` - Sets up required environment variables for the deployment
- `get-your-copy.sh` - Downloads a local copy of this reference architecture

**Testing and Utilities:**
- `tests/utils/generate-identity-secrets.sh` - Generates Camunda Identity secrets
- `tests/utils/camunda-base-values.yml` - Base Helm values for Camunda Platform
- `tests/utils/camunda-domain-values.yml` - Domain-specific Helm values
- `tests/utils/camunda-values-identity-secrets.yml` - Identity secrets configuration
- `tests/utils/get-oc-app-domain.sh` - OpenShift domain utility (placeholder)

**Platform-Specific Files:**
- `postgresql/deploy-openshift.sh` - OpenShift-specific PostgreSQL deployment
- `keycloak/keycloak-instance-domain-openshift.yml` - OpenShift route configuration for Keycloak
- `keycloak/keycloak-instance-domain-nginx.yml` - Nginx ingress configuration for Keycloak

**Documentation:**
- `camunda-operator-deployment-blog.md` - Blog post content about operator-based deployment

## Next Steps

After infrastructure deployment:

2. **Install Camunda Helm chart** with operator-based infrastructure
3. **Configure monitoring** (Prometheus, Grafana)
4. **Set up TLS** for production deployments

## Cleanup

To remove all components:
```bash
# Remove Camunda Platform
helm uninstall camunda -n camunda

# Remove infrastructure components
kubectl delete namespace camunda

# Remove operators (if installed in separate namespaces)
kubectl delete namespace cnpg-system      # CloudNativePG operator
kubectl delete namespace elastic-system   # ECK operator
# Note: Keycloak operator is installed in the camunda namespace
```

**Note:** This will delete all data. For production, ensure proper backup procedures.



<!-- TODO: handle images used by the operators (SBOM) -->

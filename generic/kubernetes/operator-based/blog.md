# Deploying Camunda 8.8 with Official Vendor-Supported Methods: A Complete Infrastructure Guide

With the upcoming release of Camunda 8.8, we continue to strengthen our commitment to robust, production-ready deployments based on solid foundations. In our [previous blog post about Helm sub-chart changes](https://camunda.com/blog/2025/08/changes-to-camunda-helm-sub-charts-what-you-need-to-know/), we explained how Bitnami's shift in container image distribution led us to disable infrastructure sub-charts by default starting with Camunda 8.8.

## Why Official Vendor Methods Matter for Camunda 8.8

As outlined in our August announcement, Camunda 8.8 reinforces our strategy of building deployments on solid foundations—primarily managed PostgreSQL and Elasticsearch services, along with external OIDC providers. However, we understand that these managed infrastructure components aren't always available in your organization's service catalog.

That's why in this blog post, we'll show you how to integrate these infrastructure components using official deployment methods that don't depend on Bitnami sub-charts. Instead, we'll use **vendor-supported deployment approaches**—the recommended way to deploy and manage these services in production environments.

Using official vendor-supported methods provides several advantages:
- **Vendor maintenance**: Each deployment method is maintained by the respective project team
- **Production-grade features**: Built-in backup, monitoring, and scaling capabilities
- **Enterprise support**: Official support channels and documentation
- **Security-focused**: Regular updates and CVE patches from upstream maintainers

## Elasticsearch with Elastic Cloud on Kubernetes (ECK)

### Introduction

[Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s) is the official Kubernetes deployment method for Elasticsearch, maintained by Elastic. ECK provides the vendor-recommended approach for deploying Elasticsearch in Kubernetes environments, automatically handling cluster deployment, scaling, upgrades, and security configuration.

For Camunda 8.8, we target Elasticsearch 8.16+ as documented in our [supported environments guide](https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements).

### Installation Steps

First, create the Elasticsearch cluster configuration file:

**Source:** [elasticsearch/elasticsearch-cluster.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/elasticsearch/elasticsearch-cluster.yml)

```yaml
---
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
    name: elasticsearch
spec:
    version: 8.19.3
    image: docker.elastic.co/elasticsearch/elasticsearch:8.19.3
    http:
        tls:
            selfSignedCertificate:
                disabled: true
    nodeSets:
        - name: masters
          count: 3
          config:
              node.store.allow_mmap: 'false'
              # Disable deprecation warnings - https://github.com/camunda/camunda/issues/26285
              # yamllint disable-line
              logger.org.elasticsearch.deprecation: OFF
          podTemplate:
              spec:
                  affinity:
                      podAntiAffinity:
                          requiredDuringSchedulingIgnoredDuringExecution:
                              - labelSelector:
                                    matchExpressions:
                                        - key: elasticsearch.k8s.elastic.co/cluster-name
                                          operator: In
                                          values:
                                              - elasticsearch
                                topologyKey: kubernetes.io/hostname
                  containers:
                      - name: elasticsearch
                        securityContext:
                            readOnlyRootFilesystem: true
                        env:
                            - name: ELASTICSEARCH_ENABLE_REST_TLS
                              value: 'false'
                            - name: READINESS_PROBE_TIMEOUT
                              value: '300'
                        resources:
                            requests:
                                cpu: 1
                                memory: 2Gi
                            limits:
                                cpu: 2
                                memory: 2Gi
          volumeClaimTemplates:
              - metadata:
                    name: elasticsearch-data
                spec:
                    accessModes: [ReadWriteOnce]
                    resources:
                        requests:
                            storage: 15Gi
```

Next, execute the deployment script:

**Source:** [elasticsearch/deploy.sh](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/elasticsearch/deploy.sh)

```bash
#!/bin/bash
# elasticsearch/deploy.sh - Deploy Elasticsearch via ECK operator

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}
OPERATOR_NAMESPACE=${1:-elastic-system}

# Install ECK operator CRDs
kubectl apply --server-side -f \
  https://download.elastic.co/downloads/eck/3.1.0/crds.yaml

# Create operator namespace if needed
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install ECK operator
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side  -f \
  https://download.elastic.co/downloads/eck/3.1.0/operator.yaml
echo "ECK operator deployed in namespace: $OPERATOR_NAMESPACE"

# Wait for operator to be ready
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=300s statefulset/elastic-operator -n "$OPERATOR_NAMESPACE"

# Deploy Elasticsearch cluster
kubectl apply -f "elasticsearch-cluster.yml" -n "$CAMUNDA_NAMESPACE"

# Wait for Elasticsearch cluster to be ready
kubectl wait --for=jsonpath='{.status.phase}'=Ready --timeout=600s elasticsearch --all -n "$CAMUNDA_NAMESPACE"

echo "Elasticsearch deployment completed in namespace: $CAMUNDA_NAMESPACE"
```

This script:
1. Installs ECK CRDs and controller components
2. Deploys the Elasticsearch cluster using the configuration above
3. Waits for the cluster to become ready

### Integration with Camunda Helm Chart

ECK automatically generates TLS certificates and authentication credentials. The integration with Camunda is seamless using the auto-generated secrets:

**Source:** [elasticsearch/camunda-values.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/elasticsearch/camunda-values.yml)

```yaml
---
# Camunda Platform 8 Values - ECK snippet
# This configuration uses external services managed by Kubernetes operators:
# - Elasticsearch: ECK operator with master-only cluster configuration (uses 'elasticsearch-es-elastic-user' secret)
#
# Authentication Secrets:
# - elasticsearch-es-elastic-user: Contains 'elastic' user password for Elasticsearch

# Global configuration
global:
    # Elasticsearch configuration
    elasticsearch:
        enabled: true
        external: true
        # URL configuration
        url:
            protocol: http
            host: elasticsearch-es-http
            port: 9200
        # Authentication using ECK-generated secret
        auth:
            username: elastic
            secret:
                existingSecret: elasticsearch-es-elastic-user
                existingSecretKey: elastic


elasticsearch:
    enabled: false
    commonLabels: {}
```

This configuration tells Camunda to:
- Use the auto-generated `elastic` user credentials
- Connect via HTTPS with ECK-managed TLS certificates
- Reference the `elasticsearch-es-elastic-user` secret created by ECK

## PostgreSQL with CloudNativePG

### Introduction

[CloudNativePG](https://cloudnative-pg.io/) is a CNCF project that provides the official Kubernetes deployment method for PostgreSQL. It's the vendor-recommended approach for cloud-native PostgreSQL deployments, designed specifically for production environments with enterprise-grade features like automated backups, point-in-time recovery, and rolling updates.

Our setup provisions three separate PostgreSQL clusters for different Camunda components, all targeting PostgreSQL 15—the common denominator across current Camunda requirements. Each component gets its own dedicated PostgreSQL cluster:

- **pg-identity**: For Camunda Identity component
- **pg-keycloak**: For Keycloak Identity service
- **pg-webmodeler**: For WebModeler component

**Note:** If you don't plan to use certain components (for example, WebModeler), you can simply remove the corresponding cluster definition from the `postgresql-clusters.yml` manifest before deployment. This approach allows you to deploy only the PostgreSQL clusters you actually need, reducing resource consumption.

### Installation Steps

First, create the PostgreSQL cluster configuration file:

**Source:** [postgresql/postgresql-clusters.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/postgresql/postgresql-clusters.yml)

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
    name: pg-identity
spec:
    instances: 1
    description: PostgreSQL cluster for Camunda Identity
    storage:
        size: 15Gi
    superuserSecret:
        name: pg-identity-superuser-secret
    seccompProfile:
        type: RuntimeDefault
    bootstrap:
        initdb:
            database: identity
            owner: identity
            dataChecksums: true
            secret:
                name: pg-identity-secret
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
    name: pg-keycloak
spec:
    instances: 1
    description: PostgreSQL cluster for Keycloak
    storage:
        size: 15Gi
    superuserSecret:
        name: pg-keycloak-superuser-secret
    seccompProfile:
        type: RuntimeDefault
    postgresql:
        parameters:
            lock_timeout: 30s
            statement_timeout: '0'
    bootstrap:
        initdb:
            database: keycloak
            owner: keycloak
            dataChecksums: true
            secret:
                name: pg-keycloak-secret
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
    name: pg-webmodeler
spec:
    instances: 1
    description: PostgreSQL cluster for Webmodeler
    superuserSecret:
        name: pg-webmodeler-superuser-secret
    seccompProfile:
        type: RuntimeDefault
    bootstrap:
        initdb:
            database: webmodeler
            owner: webmodeler
            secret:
                name: pg-webmodeler-secret
    storage:
        size: 15Gi
```

You'll also need the secrets configuration script:

**Source:** [postgresql/set-secrets.sh](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/postgresql/set-secrets.sh)

```bash
wget https://raw.githubusercontent.com/camunda/camunda-deployment-references/feature/operator-playground/generic/kubernetes/operator-based/postgresql/set-secrets.sh
chmod +x set-secrets.sh
```

Next, execute the deployment script:

**Source:** [postgresql/deploy.sh](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/postgresql/deploy.sh)

```bash
#!/bin/bash
# postgresql/deploy.sh - Deploy PostgreSQL via CloudNativePG operator

set -euo pipefail

# Variables
NAMESPACE=${NAMESPACE:-camunda}
OPERATOR_NAMESPACE=${1:-cnpg-system}

# TODO: renovate

# Install CloudNativePG operator CRDs and operator
kubectl apply -n "$OPERATOR_NAMESPACE" --server-side -f \
      "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml"

# Wait for operator to be ready
kubectl rollout status deployment \
  -n "$OPERATOR_NAMESPACE" cnpg-controller-manager
echo "CloudNativePG operator deployed in namespace: $OPERATOR_NAMESPACE"

# Create PostgreSQL secrets
NAMESPACE="$NAMESPACE" "./set-secrets.sh"

# Deploy PostgreSQL
kubectl apply --server-side -f "postgresql-clusters.yml" -n "$NAMESPACE"

# Wait for PostgreSQL cluster to be ready
kubectl wait --for=condition=Ready --timeout=600s cluster --all -n "$NAMESPACE"

echo "PostgreSQL deployment completed in namespace: $NAMESPACE"
```

This script:
1. Installs the CloudNativePG management components
2. Creates authentication secrets for each database
3. Deploys the three PostgreSQL clusters using the configuration above
4. Waits for all clusters to become ready

For OpenShift environments, use [this dedicated script](https://raw.githubusercontent.com/camunda/camunda-deployment-references/feature/operator-playground/generic/kubernetes/operator-based/postgresql/deploy-openshift.sh).


### Integration with Camunda Helm Chart

PostgreSQL integration is configured through separate values files for each component:

**For Camunda Identity:**

**Source:** [postgresql/camunda-identity-values.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/postgresql/camunda-identity-values.yml)

```yaml
---
# Camunda Platform 8 Values - Identity CloudNativePG snippet
# This configuration uses external services managed by Kubernetes operators:
# - PostgreSQL: CloudNativePG operator with dedicated cluster for Identity (uses 'pg-identity-secret' secret)
#
# Authentication Secrets:
# - pg-identity-secret: Contains username/password for Identity database

# Global configuration
global:
    identity:
        database:
            enabled: true
            external: true
            # Database connection details
            host: pg-identity-rw  # CloudNativePG service name
            port: 5432
            name: identity
            # Authentication using CloudNativePG-generated secret
            auth:
                username: identity
                secret:
                    existingSecret: pg-identity-secret
                    existingSecretPasswordKey: password


identity:
    enabled: true
    database:
        enabled: false
```

**For WebModeler:**

**Source:** [postgresql/camunda-webmodeler-values.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/postgresql/camunda-webmodeler-values.yml)

```yaml
---
# Camunda Platform 8 Values - WebModeler CloudNativePG snippet
# This configuration uses external services managed by Kubernetes operators:
# - PostgreSQL: CloudNativePG operator with dedicated cluster for WebModeler (uses 'pg-webmodeler-secret' secret)
#
# Authentication Secrets:
# - pg-webmodeler-secret: Contains username/password for WebModeler database

# Global configuration
global:
    identity:
        database:
            enabled: true
            external: true
            # Database connection details
            host: pg-webmodeler-rw  # CloudNativePG service name
            port: 5432
            name: webmodeler
            # Authentication using CloudNativePG-generated secret
            auth:
                username: webmodeler
                secret:
                    existingSecret: pg-webmodeler-secret
                    existingSecretPasswordKey: password


webModeler:
    enabled: true
    database:
        enabled: false
```

These configurations reference the auto-generated database credentials and connection details, ensuring secure communication between Camunda components and their respective databases.

## Keycloak with the Official Keycloak Deployment Method

### Introduction

The [Keycloak deployment for Kubernetes](https://www.keycloak.org/operator/installation) is the official vendor-supported way to deploy and manage Keycloak instances on Kubernetes. Maintained by the Keycloak team, it provides the recommended approach for automated deployment, configuration, and lifecycle management.

We target Keycloak 26+ as specified in our [supported environments documentation](https://docs.camunda.io/docs/next/reference/supported-environments/#component-requirements).

### Installation Steps

First, create the Keycloak instance configuration file:

**Source:** [keycloak/keycloak-instance-no-domain.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/keycloak/keycloak-instance-no-domain.yml)

```yaml
---
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
    name: keycloak
spec:
    instances: 1
    db:
        host: pg-keycloak-rw # this service is provided by the CNPG keycloak
        port: 5432
        database: keycloak
        schema: public
        usernameSecret:
            name: pg-keycloak-secret
            key: username
        passwordSecret:
            name: pg-keycloak-secret
            key: password
    http:
        httpEnabled: true
    transaction:
        xaEnabled: false
    additionalOptions:
        - name: http-relative-path
          value: /auth
    ingress:
        enabled: false
    hostname:
        hostname: localhost
        strict: false
    resources:
        limits:
            cpu: 500m
            memory: 1Gi
        requests:
            cpu: 250m
            memory: 512Mi
```

Next, execute the deployment script:

**Source:** [keycloak/deploy.sh](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/keycloak/deploy.sh)

```bash
#!/bin/bash
# keycloak/deploy.sh - Deploy Keycloak via Keycloak operator (requires PostgresSQL)

set -euo pipefail

# Variables
CAMUNDA_NAMESPACE=${CAMUNDA_NAMESPACE:-camunda}

# TODO: renovate keycloak version

# Install Keycloak operator CRDs
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml


# Install Keycloak operator
kubectl apply -n "$CAMUNDA_NAMESPACE" --server-side -f \
  https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.3.3/kubernetes/kubernetes.yml


# Wait for operator to be ready
kubectl wait --for=condition=available --timeout=300s deployment/keycloak-operator -n "$CAMUNDA_NAMESPACE"
echo "Keycloak operator deployed in namespace: $CAMUNDA_NAMESPACE"

# Deploy Keycloak
kubectl apply -f "keycloak-instance-no-domain.yml" -n "$CAMUNDA_NAMESPACE"

# Wait for Keycloak instance to be ready
kubectl wait --for=condition=Ready --timeout=600s keycloak --all -n "$CAMUNDA_NAMESPACE"

echo "Keycloak deployment completed in namespace: $CAMUNDA_NAMESPACE"
```

This script:
1. Installs Keycloak CRDs and controller components
2. Deploys the Keycloak instance using the configuration above
3. Configures the instance to serve under the `/auth` path prefix
4. Waits for the instance to become ready

### Additional Configuration Options

Different manifests are available for various deployment topologies:

- **For Nginx ingress with custom domains:** [keycloak-instance-domain-nginx.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/keycloak/keycloak-instance-domain-nginx.yml)
- **For OpenShift with route configuration:** [keycloak-instance-domain-openshift.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/keycloak/keycloak-instance-domain-openshift.yml)

### Integration with Camunda Helm Chart

Keycloak integration also varies based on your domain configuration:

- **For domain-based deployments:** [camunda-keycloak-domain-values.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/keycloak/camunda-keycloak-domain-values.yml)
- **For local/port-forward access:** [camunda-keycloak-no-domain-values.yml](https://github.com/camunda/camunda-deployment-references/blob/feature/operator-playground/generic/kubernetes/operator-based/keycloak/camunda-keycloak-no-domain-values.yml)

The Keycloak deployment automatically creates admin credentials and configures the Keycloak realm for Camunda integration.

## Putting It All Together: Complete Camunda 8.8 Deployment

Once you have deployed the infrastructure components using the official vendor methods above, you can install Camunda Platform 8.8 by combining the configuration files as described in our [official installation guide](https://docs.camunda.io/docs/next/self-managed/installation-methods/helm/install/).

### Deploy Camunda Platform

Deploy Camunda using Helm with the vendor-supported infrastructure configurations:

```bash
helm install camunda camunda/camunda-platform --version 8.8 \
    --values https://helm.camunda.io/camunda-platform/values/values-v8.8.yaml \
    --values camunda-identity-values.yml \
    --values camunda-webmodeler-values.yml \
    --values camunda-elastic-values.yml \
    --values camunda-keycloak-no-domain-values.yml
```

This approach gives you:
- **Production-ready infrastructure** managed by official vendor-supported methods
- **Security by default** with auto-generated TLS certificates and credentials
- **Operational excellence** with built-in monitoring, backup, and scaling capabilities
- **Future-proof architecture** that doesn't depend on deprecated Bitnami sub-charts

## What's Next?

We're committed to making this transition as smooth as possible. In the coming months, expect:

- **Enhanced migration guides** for existing deployments using Bitnami sub-charts
- **Automated migration tools** to help transition from sub-charts to vendor-supported deployments
- **Consolidated documentation** bringing together all official deployment options
- **Extended support** for additional infrastructure scenarios and cloud providers

This vendor-supported approach represents the future of cloud-native Camunda deployments. By leveraging the expertise of upstream maintainers and following industry best practices, you'll have a more robust, secure, and maintainable Camunda Platform installation.

For questions or feedback, join the discussion on our [community forum](https://forum.camunda.io/).

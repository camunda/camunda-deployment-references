# Deployment Guide - Operator-based Camunda Infrastructure

This guide provides the minimal steps to deploy a complete Camunda Platform 8 infrastructure using Kubernetes operators.

## Prerequisites

- Kubernetes cluster (standard Kubernetes or OpenShift)
- `kubectl` configured and connected to your cluster
- `helm` CLI installed
- `envsubst` available (for environment variable substitution)

## Environment Variables

Source the environment configuration:

```bash
# Load environment variables from 0-set-environment.sh
source 0-set-environment.sh
```

Or set them manually:

```bash
export CAMUNDA_NAMESPACE="camunda"
export CAMUNDA_DOMAIN="localhost"
export CAMUNDA_PROTOCOL="http"
export CAMUNDA_HELM_CHART_VERSION="0.0.0-snapshot-alpha"
```

## Quick Deployment (All-in-One)

For a complete deployment with default settings:

```bash
# 1. Source environment variables
source 0-set-environment.sh

# 2. Deploy all infrastructure components (PostgreSQL, Elasticsearch, Keycloak)
./deploy-all-reqs.sh

# 3. Create Camunda credentials
./04-camunda-create-identity-secret.sh

# 4. Deploy Camunda Platform
./04-camunda-deploy.sh

# 6. Verify complete deployment
./check-deployment-ready.sh
```

## Step-by-Step Deployment

### 1. PostgreSQL Operator and Clusters

```bash
# Install CloudNativePG operator
./01-postgresql-install-operator.sh cnpg-system

# Create database secrets
./01-postgresql-create-secrets.sh $CAMUNDA_NAMESPACE

# Deploy PostgreSQL clusters
kubectl apply -n $CAMUNDA_NAMESPACE -f 01-postgresql-clusters.yml

# Wait for clusters to be ready
./01-postgresql-wait-ready.sh $CAMUNDA_NAMESPACE
```

### 2. Elasticsearch Operator and Cluster

```bash
# Install ECK operator
./02-elasticsearch-install-operator.sh elastic-system

# Deploy Elasticsearch cluster
kubectl apply -n $CAMUNDA_NAMESPACE -f 02-elasticsearch-cluster.yml

# Wait for cluster to be ready
./02-elasticsearch-wait-ready.sh $CAMUNDA_NAMESPACE

# Get admin credentials
./02-elasticsearch-get-admin-credentials.sh $CAMUNDA_NAMESPACE
```

### 3. Keycloak Operator and Instance

```bash
# Install Keycloak operator
./03-keycloak-install-operator.sh $CAMUNDA_NAMESPACE

# Deploy Keycloak instance
envsubst < 03-keycloak-instance.yml | kubectl apply -n $CAMUNDA_NAMESPACE -f -

# Wait for Keycloak to be ready
./03-keycloak-wait-ready.sh $CAMUNDA_NAMESPACE

# Get admin credentials
./03-keycloak-get-admin-credentials.sh $CAMUNDA_NAMESPACE
```

### 4. Camunda Credentials and Platform

```bash
# Create Identity secrets
./04-camunda-create-identity-secret.sh $CAMUNDA_NAMESPACE

# Deploy Camunda Platform
./04-camunda-deploy.sh $CAMUNDA_NAMESPACE

# Wait for Camunda to be ready
./04-camunda-wait-ready.sh $CAMUNDA_NAMESPACE

# Verify deployment
./04-camunda-verify.sh $CAMUNDA_NAMESPACE
```

## Verification Steps

After deployment, verify each component:

```bash
# Check all infrastructure components
./verify-all-reqs.sh $CAMUNDA_NAMESPACE

# Check Camunda Platform specifically
./04-camunda-verify.sh $CAMUNDA_NAMESPACE
```

## Access Applications

### Port Forwarding (for localhost access)

```bash
# Camunda applications
kubectl port-forward -n $CAMUNDA_NAMESPACE svc/camunda-operate 8081:80
kubectl port-forward -n $CAMUNDA_NAMESPACE svc/camunda-tasklist 8082:80
kubectl port-forward -n $CAMUNDA_NAMESPACE svc/camunda-optimize 8083:80
kubectl port-forward -n $CAMUNDA_NAMESPACE svc/camunda-identity 8084:80
kubectl port-forward -n $CAMUNDA_NAMESPACE svc/camunda-console 8085:80

# Keycloak admin
kubectl port-forward -n $CAMUNDA_NAMESPACE svc/keycloak-service 8080:8080
```

### Default Credentials

#### Camunda Identity First User
- Username: `admin`
- Password: Check the output of `./04-camunda-create-identity-secret.sh` or run:
  ```bash
  kubectl get secret camunda-credentials -n $CAMUNDA_NAMESPACE -o jsonpath='{.data.identity-firstuser-password}' | base64 -d
  ```

#### Keycloak Admin
- Username: `temp-admin`
- Password: Run `./03-keycloak-get-admin-credentials.sh $CAMUNDA_NAMESPACE`

#### Elasticsearch Admin
- Username: `elastic`
- Password: Run `./02-elasticsearch-get-admin-credentials.sh $CAMUNDA_NAMESPACE`

## Customization Options

### Skip Components

The `deploy-all-reqs.sh` script supports skipping components:

```bash
# Skip PostgreSQL (if using external database)
./deploy-all-reqs.sh --skip-postgresql

# Skip Elasticsearch (if using external search engine)
./deploy-all-reqs.sh --skip-elasticsearch

# Skip Keycloak (if using external identity provider)
./deploy-all-reqs.sh --skip-keycloak

# Skip CRD installation (if operators already installed)
./deploy-all-reqs.sh --skip-crds
```

### Custom Operator Namespaces

```bash
# Use custom namespaces for operators
./deploy-all-reqs.sh \
  --postgresql-operator-ns my-cnpg-system \
  --elasticsearch-operator-ns my-elastic-system \
  --keycloak-operator-ns my-keycloak-system
```

## Troubleshooting

### Check Pod Status

```bash
# All pods in namespace
kubectl get pods -n $CAMUNDA_NAMESPACE

# Specific component logs
kubectl logs -n $CAMUNDA_NAMESPACE -l app.kubernetes.io/name=operate
kubectl logs -n $CAMUNDA_NAMESPACE -l app.kubernetes.io/name=zeebe-gateway
```

### Check Operator Status

```bash
# PostgreSQL operator
kubectl get pods -n cnpg-system

# Elasticsearch operator
kubectl get pods -n elastic-system

# Keycloak operator
kubectl get pods -n $CAMUNDA_NAMESPACE -l name=keycloak-operator
```

### Common Issues

1. **OpenShift Security Context Issues**: The deployment automatically detects OpenShift and applies compatibility settings
2. **Resource Limits**: Ensure your cluster has sufficient resources (see individual component requirements)
3. **Network Policies**: Check if network policies allow communication between components
4. **Storage Classes**: Ensure default storage class is available for persistent volumes

## Cleanup

To remove the deployment:

```bash
# Remove Camunda Platform
helm uninstall camunda -n $CAMUNDA_NAMESPACE

# Remove operator-managed resources
kubectl delete -n $CAMUNDA_NAMESPACE -f 03-keycloak-instance.yml
kubectl delete -n $CAMUNDA_NAMESPACE -f 02-elasticsearch-cluster.yml
kubectl delete -n $CAMUNDA_NAMESPACE -f 01-postgresql-clusters.yml

# Remove secrets
kubectl delete secret -n $CAMUNDA_NAMESPACE camunda-credentials
kubectl delete secret -n $CAMUNDA_NAMESPACE pg-identity-secret pg-webmodeler-secret

# Remove namespace
kubectl delete namespace $CAMUNDA_NAMESPACE

# Remove operators (optional)
kubectl delete namespace cnpg-system elastic-system
```

## Next Steps

- Configure ingress for external access
- Set up monitoring and alerting
- Configure backup strategies
- Review security settings for production use

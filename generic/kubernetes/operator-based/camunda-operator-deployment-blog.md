# Deploying Camunda 8 Orchestration with Kubernetes Operators: Migrating from Bitnami to Official Operators

Camunda 8 is evolving towards a more cloud-native approach by leveraging Kubernetes operators for infrastructure management. This guide walks you through deploying Camunda orchestration components using official operators instead of the traditional Bitnami charts, providing better lifecycle management, security, and operational excellence.

## Why Migrate to Operators?

The shift from Bitnami-based deployments to Kubernetes operators offers several advantages:

- **Official Support**: Direct integration with vendor-supported operators (ECK for Elasticsearch, CNPG for PostgreSQL)
- **Enhanced Security**: Operator-managed certificates, secrets rotation, and security contexts
- **Better Lifecycle Management**: Automated upgrades, backup management, and scaling
- **Production Readiness**: Battle-tested operators used in enterprise environments
- **Simplified Operations**: Declarative configuration with automated operational tasks

## Prerequisites

Before starting, ensure you have:

- Kubernetes cluster with sufficient permissions to install CRDs and cluster roles
- `kubectl` configured with cluster admin access
- Helm 3.x installed
- `curl` and `jq` for verification steps
- A dedicated namespace for the deployment

## Step 1: Get Your Copy of the Reference Architecture

First, clone the Camunda deployment references repository to access the operator-based deployment scripts:

```bash
# Clone the repository with the operator-based reference architecture
git clone --depth 1 --branch feature/operator-playground https://github.com/camunda/camunda-deployment-references.git

# Navigate to the operator-based deployment directory
cd camunda-deployment-references/generic/kubernetes/operator-based

echo "You are now in the reference architecture directory $(pwd)."
```

This repository contains all the necessary scripts, YAML manifests, and Helm values files for a production-ready operator-based deployment.

## Step 2: Configure Your Deployment

Set up the environment variables that will be used throughout the deployment process:

```bash
# Source the environment configuration
source 0-set-environment.sh
```

This script sets up the following key variables:

```bash
export CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
export CAMUNDA_HELM_CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-0.0.0-snapshot-alpha}"
```

**Output:**
```
Environment variables set:
  CAMUNDA_NAMESPACE=camunda
  CAMUNDA_HELM_CHART_VERSION=0.0.0-snapshot-alpha
```

You can customize these variables according to your environment requirements before sourcing the script.

## Step 3: Deploy Elasticsearch with ECK Operator

Deploy the Elasticsearch infrastructure using the Elastic Cloud on Kubernetes (ECK) operator. This step requires cluster-admin privileges to install Custom Resource Definitions (CRDs) and cluster roles.

### Using the Automated Script

The easiest way to deploy only Elasticsearch is using the provided script:

```bash
# Deploy only Elasticsearch infrastructure (skip PostgreSQL and Keycloak)
./deploy-all-reqs.sh --skip-postgresql --skip-keycloak
```

**Expected Output:**
```
Starting deployment with the following configuration:
  Application namespace: camunda
  PostgreSQL operator namespace: cnpg-system (SKIPPED)
  Elasticsearch operator namespace: elastic-system
  Keycloak operator namespace: camunda (SKIPPED)

Installing Elasticsearch operator in namespace: elastic-system
namespace/elastic-system created
customresourcedefinition.apiextensions.k8s.io/agents.agent.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/apmservers.apm.k8s.elastic.co created
customresourcedefinition.apiextensions.k8s.io/beats.beat.k8s.elastic.co created
...

Waiting for Elasticsearch operator to be ready...
deployment.apps/elastic-operator condition met

Deploying Elasticsearch cluster...
elasticsearch.elasticsearch.k8s.elastic.co/elasticsearch created

Waiting for Elasticsearch cluster to be ready...
✓ Elasticsearch cluster is ready and healthy
```

### Understanding the Elasticsearch Configuration

The deployment creates an Elasticsearch cluster using the configuration in `02-elasticsearch-cluster.yml`:

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
    name: elasticsearch
spec:
    version: 8.18.0
    http:
        tls:
            selfSignedCertificate:
                disabled: true  # HTTP mode for development
    nodeSets:
        - name: masters
          count: 3
          config:
              node.store.allow_mmap: 'false'
              logger.org.elasticsearch.deprecation: "OFF"
          # Pod anti-affinity for high availability
          # Resource limits: 1-2 CPU, 2Gi memory
```

### Required Permissions

The deployment script requires the following Kubernetes permissions:

- **Cluster Admin**: To install CRDs and cluster roles
- **Namespace Creation**: To create dedicated operator namespaces
- **Service Account Management**: To create operator service accounts
- **RBAC Management**: To bind appropriate roles to service accounts

## Step 4: Install Camunda Platform

Once Elasticsearch is ready and healthy, deploy the Camunda platform using the operator-managed infrastructure:

```bash
# Install Camunda using the orchestration-only Helm values
helm upgrade --install camunda oci://ghcr.io/camunda/helm/camunda-platform \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "$CAMUNDA_NAMESPACE" \
    --create-namespace \
    --values values-orchestration-only.yml \
    --set global.compatibility.openshift.adaptSecurityContext=force \
    --wait --timeout 10m
```

**Expected Output:**
```
Release "camunda" does not exist. Installing it now.
Pulled: ghcr.io/camunda/helm/camunda-platform:0.0.0-snapshot-alpha
Digest: sha256:a1b2c3d4e5f6...
NAME: camunda
LAST DEPLOYED: Thu Sep 12 10:30:00 2025
NAMESPACE: camunda
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
## Camunda Platform 8

Your Camunda Platform 8 deployment is ready!

### Accessing the Applications

Zeebe Gateway: camunda-zeebe-gateway:26500
Operate: http://localhost:8081/operate
Tasklist: http://localhost:8081/tasklist
```

### Key Configuration Highlights

The `values-orchestration-only.yml` file configures Camunda to use the operator-managed Elasticsearch:

```yaml
global:
    elasticsearch:
        enabled: true
        external: true
        url:
            protocol: http
            host: elasticsearch-es-http
            port: 9200
        auth:
            username: elastic
            secret:
                existingSecret: elasticsearch-es-elastic-user
                existingSecretKey: elastic

elasticsearch:
    enabled: false  # Use external Elasticsearch
```

## Step 5: Verify the Deployment

Confirm that your Camunda deployment is working correctly by checking the Zeebe cluster topology:

```bash
# Port-forward to access Camunda Gateway (run in separate terminal)
kubectl port-forward svc/camunda-zeebe-gateway 8081:8080 -n "$CAMUNDA_NAMESPACE" &

# Verify the cluster topology
curl -u demo:demo http://localhost:8081/orchestration/v2/topology | jq
```

**Expected Output:**
```json
{
  "brokers": [
    {
      "nodeId": 0,
      "host": "camunda-zeebe-0.camunda-zeebe.camunda.svc.cluster.local",
      "port": 26501,
      "partitions": [
        {
          "partitionId": 1,
          "role": "LEADER",
          "health": "HEALTHY"
        }
      ],
      "version": "8.6.0"
    }
  ],
  "clusterSize": 1,
  "partitionsCount": 1,
  "replicationFactor": 1,
  "gatewayVersion": "8.6.0"
}
```

### Additional Verification Steps

Check the status of all deployed components:

```bash
# Check Elasticsearch cluster status
kubectl get elasticsearch -n "$CAMUNDA_NAMESPACE"

# Check Camunda pods status
kubectl get pods -n "$CAMUNDA_NAMESPACE"

# Check Elasticsearch operator logs if needed
kubectl logs -n elastic-system deployment/elastic-operator
```

**Expected Pod Status:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
elasticsearch-es-masters-0             1/1     Running   0          5m
elasticsearch-es-masters-1             1/1     Running   0          5m
elasticsearch-es-masters-2             1/1     Running   0          5m
camunda-operate-5d7f8b9c8d-xyz12       1/1     Running   0          3m
camunda-tasklist-7b6d9c4f5e-abc34      1/1     Running   0          3m
camunda-zeebe-0                        1/1     Running   0          3m
camunda-zeebe-gateway-8f5c2d1a9b-def56 1/1     Running   0          3m
```

## Troubleshooting Common Issues

### Elasticsearch Not Ready

If Elasticsearch takes time to become ready:

```bash
# Check Elasticsearch status
kubectl describe elasticsearch elasticsearch -n "$CAMUNDA_NAMESPACE"

# Check pod events
kubectl describe pod elasticsearch-es-masters-0 -n "$CAMUNDA_NAMESPACE"

# Check operator logs
kubectl logs -n elastic-system deployment/elastic-operator --tail=50
```

### Camunda Pods CrashLooping

Check if Elasticsearch connectivity is the issue:

```bash
# Test Elasticsearch connectivity from within the cluster
kubectl run debug --image=curlimages/curl -i --rm --restart=Never -- \
  curl -s http://elasticsearch-es-http.camunda.svc.cluster.local:9200/_cluster/health
```

### Permission Issues

Ensure your user has the required cluster permissions:

```bash
# Check if you can create CRDs
kubectl auth can-i create customresourcedefinitions

# Check if you can create cluster roles
kubectl auth can-i create clusterroles
```

## Production Considerations

### Security Hardening

For production deployments, consider enabling TLS:

```yaml
# In 02-elasticsearch-cluster.yml
http:
  tls:
    selfSignedCertificate:
      disabled: false  # Enable TLS
```

### Resource Planning

Adjust resource allocations based on your workload:

```yaml
# In 02-elasticsearch-cluster.yml
resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi
```

### High Availability

For production, consider:
- Multi-zone node distribution
- Persistent volume classes with appropriate storage classes
- Network policies for security isolation
- Monitoring and alerting setup

## Conclusion

Migrating from Bitnami-based deployments to Kubernetes operators provides a more robust, secure, and maintainable foundation for Camunda 8 orchestration. The operator-based approach offers:

- **Simplified Operations**: Automated lifecycle management through operators
- **Enhanced Security**: Vendor-supported security contexts and certificate management
- **Better Integration**: Native Kubernetes patterns and CRDs
- **Production Readiness**: Battle-tested operators used in enterprise environments

This deployment pattern establishes a solid foundation for scaling Camunda 8 in production environments while maintaining operational excellence through cloud-native practices.

For the complete reference architecture and additional deployment options, visit the [Camunda Deployment References](https://github.com/camunda/camunda-deployment-references) repository.

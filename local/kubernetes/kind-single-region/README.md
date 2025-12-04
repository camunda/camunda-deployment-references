# Camunda 8 on Kind (Local Development)

Local Kubernetes development environment for Camunda 8 Self-Managed using Kind.

## Overview

Two deployment modes are available:

| Mode | Access | Requirements |
|------|--------|--------------|
| **Domain** | `https://camunda.example.com` | mkcert, hosts file |
| **No-domain** | `localhost` via port-forward | None |

## Prerequisites

Tools can be installed via [asdf](https://asdf-vm.com/) using the versions defined in [`.tool-versions`](../../../.tool-versions) at the repository root:

```bash
# From repository root
asdf install
```

Or install manually:

| Tool | Installation |
|------|--------------|
| [Docker](https://docs.docker.com/get-docker/) | See Docker docs |
| [Kind](https://kind.sigs.k8s.io/) | `brew install kind` or `asdf install kind` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `brew install kubectl` or `asdf install kubectl` |
| [Helm](https://helm.sh/) | `brew install helm` or `asdf install helm` |
| [mkcert](https://github.com/FiloSottile/mkcert) | `brew install mkcert` or `asdf install mkcert` (domain mode only) |

> **Note**: CI tests use the versions specified in `.tool-versions` to ensure consistency.

**Resources**: Docker with 8+ CPU cores, 12GB+ RAM recommended.

## Quick Start

All commands must be run from this directory (`local/kubernetes/kind-single-region/`).

### Option 1: Domain Mode (TLS)

```bash
make domain.init
```

Access: https://camunda.example.com

### Option 2: No-Domain Mode (Port-Forward)

```bash
make no-domain.init
```

Then start port-forwarding:
```bash
./procedure/port-forward.sh
```

## Step-by-Step Setup

### Domain Mode

```bash
# 1. Create Kind cluster
./procedure/cluster-create.sh

# 2. Deploy Ingress NGINX
./procedure/ingress-nginx-deploy.sh

# 3. Configure CoreDNS for internal domain resolution
./procedure/coredns-config.sh

# 4. Add hosts entries (requires sudo)
./procedure/hosts-add.sh

# 5. Generate TLS certificates
./procedure/certs-generate.sh

# 6. Create TLS secret in Kubernetes
./procedure/certs-create-secret.sh

# 7. Create CA ConfigMap for pod trust
./procedure/certs-create-ca-configmap.sh

# 8. Deploy Camunda
./procedure/camunda-deploy-domain.sh
```

### No-Domain Mode

```bash
# 1. Create Kind cluster
./procedure/cluster-create.sh

# 2. Deploy Ingress NGINX
./procedure/ingress-nginx-deploy.sh

# 3. Deploy Camunda
./procedure/camunda-deploy-no-domain.sh

# 4. Start port-forwarding
./procedure/port-forward.sh
```

## Accessing Camunda

### Domain Mode

| Component | URL |
|-----------|-----|
| Zeebe REST API | https://camunda.example.com/ |
| Operate | https://camunda.example.com/operate |
| Tasklist | https://camunda.example.com/tasklist |
| Identity | https://camunda.example.com/identity |
| Optimize | https://camunda.example.com/optimize |
| Keycloak | https://camunda.example.com/auth |

### No-Domain Mode (with port-forward)

| Component | URL | Description |
|-----------|-----|-------------|
| Zeebe Gateway (gRPC) | localhost:26500 | Process deployment and execution |
| Zeebe Gateway (HTTP) | http://localhost:8080/ | Zeebe REST API |
| Operate | http://localhost:8080/operate | Monitor process instances |
| Tasklist | http://localhost:8080/tasklist | Complete user tasks |
| Identity | http://localhost:8080/identity | User and permission management for the orchestration cluster |
| Optimize | http://localhost:8083 | Process analytics |
| Web Modeler | http://localhost:8070 | Design and deploy processes |
| Console | http://localhost:8087 | Manage clusters and APIs |
| Connectors | http://localhost:8085 | External system integrations |
| Management Identity | http://localhost:18081 | User and permission management |
| Keycloak | http://localhost:18080 | Authentication server |

### Default Credentials

Username: `demo`

Get password:
```bash
./procedure/get-password.sh
```

## Cleanup

### Domain Mode
```bash
make domain.clean
```

### No-Domain Mode
```bash
make no-domain.clean
```

### Individual Commands

```bash
# Uninstall Camunda
make camunda.uninstall

# Delete cluster
make cluster.delete

# Remove hosts entries
make hosts.remove

# Clean certificates
make certs.clean
```

## Makefile Reference

```bash
make help
```

| Target | Description |
|--------|-------------|
| `domain.init` | Full setup with TLS |
| `domain.clean` | Full cleanup (domain) |
| `no-domain.init` | Full setup without TLS |
| `no-domain.clean` | Full cleanup (no-domain) |
| `cluster.create` | Create Kind cluster |
| `cluster.delete` | Delete Kind cluster |
| `ingress.deploy` | Deploy Ingress NGINX |
| `hosts.add` | Add /etc/hosts entries |
| `hosts.remove` | Remove /etc/hosts entries |
| `certs.generate` | Generate TLS certificates |
| `camunda.deploy-domain` | Deploy Camunda (domain) |
| `camunda.deploy-no-domain` | Deploy Camunda (no-domain) |
| `camunda.uninstall` | Uninstall Camunda |
| `status` | Show cluster status |
| `port-forward` | Start port-forwarding |
| `get-password` | Get admin password |

## Directory Structure

```
kind-single-region/
├── configs/
│   ├── kind-cluster-config.yaml    # Kind cluster (1 control-plane + 2 workers)
│   └── coredns-configmap.yaml      # CoreDNS domain resolution
├── helm-values/
│   ├── values-domain.yml           # Helm values (domain mode)
│   ├── values-no-domain.yml        # Helm values (no-domain mode)
│   └── values-mkcert.yml           # CA trust configuration for pods
├── procedure/
│   ├── cluster-create.sh           # Create Kind cluster
│   ├── ingress-nginx-deploy.sh     # Deploy Ingress NGINX
│   ├── coredns-config.sh           # Configure CoreDNS
│   ├── hosts-add.sh                # Add /etc/hosts entries
│   ├── certs-generate.sh           # Generate TLS certificates (mkcert)
│   ├── certs-create-secret.sh      # Create TLS secret in Kubernetes
│   ├── certs-create-ca-configmap.sh # Create CA ConfigMap for pod trust
│   ├── camunda-deploy-domain.sh    # Deploy Camunda (domain mode)
│   ├── camunda-deploy-no-domain.sh # Deploy Camunda (no-domain mode)
│   ├── port-forward.sh             # Start all port-forwards
│   └── get-password.sh             # Get admin password
├── Makefile
└── README.md
```

## Technical Details

### Kind Cluster

The cluster is configured with:
- 1 control-plane node (with port mappings 80/443)
- 2 worker nodes
- Ingress NGINX deployed on control-plane with `hostNetwork: true`

### DNS Resolution in Pods

CoreDNS is configured to rewrite DNS queries for `camunda.example.com` to the ingress controller service, enabling pods to communicate via the domain name.

### TLS Certificate Trust

The mkcert CA certificate is distributed to pods via a ConfigMap (`mkcert-ca`):

- **Java pods**: CA imported into custom truststore via initContainer
- **Node.js pods**: `NODE_EXTRA_CA_CERTS` environment variable

## Troubleshooting

### Certificate Errors in Browser

```bash
mkcert -install
./procedure/certs-generate.sh
./procedure/certs-create-secret.sh
```

### Pods Not Starting

```bash
kubectl get pods -n camunda
kubectl describe pod <pod-name> -n camunda
kubectl logs <pod-name> -n camunda
```

### Ingress Not Working

```bash
kubectl get pods -n ingress-nginx
kubectl get ingress -n camunda
```

### Port-Forward Issues

If some services fail to port-forward, they may not be deployed. Check:
```bash
kubectl get svc -n camunda
```

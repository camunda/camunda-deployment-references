# Manual Deployment: Azure AKS Single Region

Use this guide when you need a fully isolated Azure environment — for example, when testing an ingress migration, validating a chart upgrade, or developing a new feature without touching CI resources.

> **Sibling variant:** `azure/kubernetes/aks-single-region-rdbms/` is a parallel scenario that uses the same Terraform modules, CI action, and procedure scripts (via symlinks). Changes to procedure scripts or Helm values in `aks-single-region/` typically need to be reflected there too.
>
> **CI equivalent:** Phases 2–3 are automated by `.github/actions/azure-kubernetes-ingress-setup/` (ingress) and `.github/workflows/azure_kubernetes_aks_single_region_tests.yml`. When changing procedure scripts or values, update those alongside this guide.

## Prerequisites

- Azure subscription with `Owner` or `Contributor` access (or ability to create Service Principals and assign roles)
- `az` CLI logged in (`az login`)
- `terraform` ≥ 1.5 (`asdf install` from repo root handles this)
- `helm` ≥ 3.10
- `kubectl`
- `yq` ≥ 4 and `envsubst` (part of `gettext`)

## Overview

The deployment consists of four phases that can be run as one sequence:

1. **Isolated Azure environment** — dedicated resource group, DNS subdomain, Service Principal
2. **Terraform** — AKS cluster, VNet, PostgreSQL Flexible Server, Key Vault, KMS
3. **Kubernetes operators** — ECK (Elasticsearch), CNPG (PostgreSQL for Keycloak), Keycloak Operator
4. **Helm** — Camunda chart with operator-assembled values

---

## Phase 0: Isolated Azure Environment

### 0.1 Region selection

> **Important:** The shared subscription enforces an Azure Policy allowing only `westeurope`, `swedencentral`, and `spaincentral`.  Check before choosing a region:
> ```bash
> az policy assignment list --query "[?displayName].{name:displayName,scope:scope}" -o table
> ```
> Also check vCPU quotas — the user node pool needs 5 × D4s\_v3 (20 vCPUs). Confirm availability:
> ```bash
> az vm list-usage --location swedencentral -o table | grep -i "standard DSv3"
> ```

Prefer **swedencentral** — geo-redundant PostgreSQL backup is supported there (spaincentral does not support it).

### 0.2 Resource group

Pre-create the resource group with the required tags **before** running Terraform — the SP will own the RG but cannot update subscription-level metadata tags itself:

```bash
az group create \
  --name rg-<your-prefix> \
  --location swedencentral \
  --tags Environment=Testing Purpose="Reference Implementation"
```

### 0.3 DNS subdomain

Create an isolated DNS zone so external-dns and cert-manager activity stays isolated from the shared zone:

```bash
az network dns zone create \
  --resource-group rg-<your-prefix> \
  --name <your-prefix>.azure.camunda.ie

# Get NS records for delegation
az network dns zone show \
  --resource-group rg-<your-prefix> \
  --name <your-prefix>.azure.camunda.ie \
  --query nameServers -o tsv
```

Delegate from the shared parent zone (`azure.camunda.ie` in `rg-infraex-global-permanent`):

```bash
az network dns record-set ns create \
  --resource-group rg-infraex-global-permanent \
  --zone-name azure.camunda.ie \
  --name <your-prefix>

for NS in <ns1> <ns2> <ns3> <ns4>; do
  az network dns record-set ns add-record \
    --resource-group rg-infraex-global-permanent \
    --zone-name azure.camunda.ie \
    --record-set-name <your-prefix> \
    --nsdname "$NS"
done
```

### 0.4 Service Principal

Create an SP with the minimum required permissions:

```bash
# Create SP scoped to the RG
SP_JSON=$(az ad sp create-for-rbac \
  --name sp-<your-prefix> \
  --role Owner \
  --scopes /subscriptions/<sub-id>/resourceGroups/rg-<your-prefix>)

# Additional subscription-level read (required for azurerm provider init)
az role assignment create \
  --assignee <client-id> \
  --role Reader \
  --scope /subscriptions/<sub-id>
```

> **Why Reader at subscription scope?** The `azurerm` provider calls `Microsoft.Resources/subscriptions/providers/read` during initialization, which requires subscription-level access even when all actual resources are in the RG.

Store credentials in `azure/kubernetes/aks-single-region/.env.local` (gitignored):

```bash
export ARM_CLIENT_ID="<client-id>"
export ARM_CLIENT_SECRET="<client-secret>"
export ARM_TENANT_ID="<tenant-id>"
export ARM_SUBSCRIPTION_ID="<sub-id>"

export AZURE_SUBSCRIPTION_ID="<sub-id>"
export AZURE_DNS_RESOURCE_GROUP="rg-<your-prefix>"
export AZURE_DNS_ZONE="<your-prefix>.azure.camunda.ie"
export TLD="<your-prefix>.azure.camunda.ie"

export CAMUNDA_DOMAIN="camunda.<your-prefix>.azure.camunda.ie"
export MAIL="your.email@camunda.com"
export EXTERNAL_DNS_OWNER_ID="<your-prefix>"
```

Also create `terraform.tfvars` (gitignored):

```hcl
subscription_id     = "<sub-id>"
terraform_sp_app_id = "<client-id>"
dns_zone_id         = "/subscriptions/<sub-id>/resourceGroups/rg-<your-prefix>/providers/Microsoft.Network/dnszones/<your-prefix>.azure.camunda.ie"
```

---

## Phase 1: Terraform

### 1.1 Local backend override

The root module defaults to an `azurerm` remote backend. Override to local state for isolated work by creating `override.tf` (gitignored):

```hcl
terraform {
  backend "local" {}
}
```

### 1.2 Set locals

Edit `main.tf` to set your prefix, resource group name, and location:

```hcl
locals {
  resource_prefix     = "<your-prefix>"
  resource_group_name = "rg-<your-prefix>"
  location            = "swedencentral"
}
```

> **Key Vault name collision:** Key Vault names are globally unique across Azure — including in soft-deleted state (90-day purge protection). If a previous deploy created a KV with this prefix, the name is locked for 90 days. Change the prefix (e.g. append a letter suffix) or explicitly purge the soft-deleted KV:
> ```bash
> az keyvault purge --name <prefix>-kv --location swedencentral
> ```

### 1.3 Apply

```bash
cd azure/kubernetes/aks-single-region
source .env.local
terraform init
terraform plan
terraform apply
```

> **IAM propagation:** If the SP was just created, role assignments may take 1–3 minutes to propagate. Confirm the SP can write before applying:
> ```bash
> az network vnet create --resource-group rg-<your-prefix> --name test-probe --location swedencentral --address-prefix 10.99.0.0/16
> az network vnet delete --resource-group rg-<your-prefix> --name test-probe
> ```

Get the cluster credentials after apply:

```bash
az aks get-credentials \
  --resource-group rg-<your-prefix> \
  --name $(terraform output -raw aks_cluster_name)
```

---

## Phase 2: Ingress components

```bash
source .env.local
source generic/kubernetes/single-region/procedure/export-ingress-setup-vars.sh

./azure/kubernetes/aks-single-region/procedure/install-contour.sh
./azure/kubernetes/aks-single-region/procedure/install-external-dns.sh
./azure/kubernetes/aks-single-region/procedure/external-dns-azure-config.sh
./generic/kubernetes/single-region/procedure/install-cert-manager-crds.sh
./azure/kubernetes/aks-single-region/procedure/install-cert-manager.sh
./azure/kubernetes/aks-single-region/procedure/install-cert-manager-issuer.sh
```

> **Contour replaces ingress-nginx** (retired March 2026). `install-contour.sh` deploys the Contour Helm chart with `envoy.service.type=LoadBalancer` and the Azure Standard LB health-probe annotation required for AKS. It sets Contour as the default IngressClass. No nginx installation needed.

---

## Phase 3: Operators and Camunda

### 3.1 Create namespace

```bash
kubectl create namespace camunda
```

### 3.2 Deploy operators (run in parallel — independent)

```bash
# ECK operator + Elasticsearch cluster
(cd generic/kubernetes/operator-based/elasticsearch && CAMUNDA_NAMESPACE=camunda ./deploy.sh) &

# CNPG operator + PostgreSQL for Keycloak
(cd generic/kubernetes/operator-based/postgresql && CAMUNDA_NAMESPACE=camunda CLUSTER_FILTER=pg-keycloak ./deploy.sh) &

wait
```

### 3.3 Deploy Keycloak operator (requires CNPG to be ready first)

For nginx-based ingress (baseline):
```bash
cd ~/Projects/camunda-deployment-references   # repo root required
CAMUNDA_NAMESPACE=camunda \
KEYCLOAK_CONFIG_FILE=generic/kubernetes/operator-based/keycloak/keycloak-instance-domain-nginx.yml \
bash generic/kubernetes/operator-based/keycloak/deploy.sh
```

For Contour-based ingress:
```bash
CAMUNDA_NAMESPACE=camunda \
KEYCLOAK_CONFIG_FILE=generic/kubernetes/operator-based/keycloak/keycloak-instance-domain-contour.yml \
bash generic/kubernetes/operator-based/keycloak/deploy.sh
```

### 3.4 Create `identity-secret-for-components`

```bash
kubectl create secret generic identity-secret-for-components \
  --namespace camunda \
  --from-literal=identity-connectors-client-token="$(openssl rand -hex 16)" \
  --from-literal=identity-console-client-token="$(openssl rand -hex 16)" \
  --from-literal=identity-webmodeler-client-token="$(openssl rand -hex 16)" \
  --from-literal=identity-orchestration-client-token="$(openssl rand -hex 16)" \
  --from-literal=identity-optimize-client-token="$(openssl rand -hex 16)" \
  --from-literal=identity-admin-client-token="$(openssl rand -hex 16)" \
  --from-literal=identity-first-user-password="$(openssl rand -hex 16)" \
  --from-literal=webmodeler-pusher-app-secret="$(openssl rand -hex 16)" \
  --from-literal=webmodeler-pusher-app-key="$(openssl rand -hex 16)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 3.5 Initialize databases

```bash
cd azure/kubernetes/aks-single-region
export DB_HOST=$(terraform output -raw postgres_fqdn)
export DB_PORT=5432
export POSTGRES_MAJOR_VERSION=$(terraform output -raw postgres_version)
export POSTGRES_ADMIN_USERNAME=$(terraform output -raw postgres_admin_username)
export POSTGRES_ADMIN_PASSWORD=$(terraform output -raw postgres_admin_password)
export DB_IDENTITY_NAME=$(terraform output -raw camunda_database_identity)
export DB_IDENTITY_USERNAME=$(terraform output -raw camunda_identity_db_username)
export DB_IDENTITY_PASSWORD=$(terraform output -raw camunda_identity_db_password)
export DB_WEBMODELER_NAME=$(terraform output -raw camunda_database_webmodeler)
export DB_WEBMODELER_USERNAME=$(terraform output -raw camunda_webmodeler_db_username)
export DB_WEBMODELER_PASSWORD=$(terraform output -raw camunda_webmodeler_db_password)
export CAMUNDA_NAMESPACE=camunda

./procedure/create-setup-db-secret.sh

kubectl apply --namespace camunda \
  -f manifests/setup-postgres-create-db.yml

kubectl wait job/create-setup-user-db --namespace camunda \
  --for=condition=complete --timeout=180s

kubectl delete job create-setup-user-db --namespace camunda
kubectl delete secret setup-db-secret --namespace camunda

./procedure/create-external-db-secrets.sh
```

### 3.6 Assemble Helm values

All commands run from the **repository root**. The env vars from step 3.5 and `.env.local` must be exported.

```bash
# Load env
source azure/kubernetes/aks-single-region/.env.local
source generic/kubernetes/single-region/procedure/chart-env.sh  # sets CAMUNDA_HELM_CHART_VERSION, CAMUNDA_NAMESPACE, CAMUNDA_RELEASE_NAME

# Load DB vars from Terraform (as in step 3.5)
export DB_HOST=$(terraform -chdir=azure/kubernetes/aks-single-region output -raw postgres_fqdn)
# ... (see step 3.5 for full list)

# Merge overlays — exact order matters
echo "{}" > values.yml
yq ". *+ load(\"azure/kubernetes/aks-single-region/helm-values/values-domain.yml\")" values.yml > values.tmp && mv values.tmp values.yml
yq ". *+ load(\"azure/kubernetes/aks-single-region/helm-values/values-contour-overlay.yml\")" values.yml > values.tmp && mv values.tmp values.yml
yq ". *+ load(\"generic/kubernetes/operator-based/elasticsearch/camunda-elastic-values.yml\")" values.yml > values.tmp && mv values.tmp values.yml
yq ". *+ load(\"generic/kubernetes/operator-based/keycloak/camunda-keycloak-domain-values.yml\")" values.yml > values.tmp && mv values.tmp values.yml
yq ". *+ load(\"generic/kubernetes/operator-based/tests/utils/camunda-values-identity-secrets.yml\")" values.yml > values.tmp && mv values.tmp values.yml

# Substitute variables
envsubst < values.yml > generated-values.yml
```

**Overlay merge order:**

| Step | File | Purpose |
|------|------|---------|
| 1 | `azure/kubernetes/aks-single-region/helm-values/values-{domain\|no-domain}.yml` | AKS-specific ingress, DB config, Orchestration settings |
| 2 | `azure/kubernetes/aks-single-region/helm-values/values-contour-overlay.yml` | Sets `ingressClassName: contour` for HTTP and gRPC; adds h2c upstream annotation to Zeebe service |
| 3 | `generic/kubernetes/operator-based/elasticsearch/camunda-elastic-values.yml` | Points Camunda at the ECK-managed ES service |
| 4 | `generic/kubernetes/operator-based/keycloak/camunda-keycloak-{domain\|no-domain}-values.yml` | Points Camunda at the operator-managed Keycloak service; sets `issuerBackendUrl` to internal service |
| 5 | `generic/kubernetes/operator-based/tests/utils/camunda-values-identity-secrets.yml` | Wires `identity-secret-for-components` into chart |

**Variables consumed by `envsubst`:**

| Variable | Source |
|----------|--------|
| `CAMUNDA_DOMAIN` | `.env.local` |
| `DB_HOST` | `terraform output -raw postgres_fqdn` |
| `DB_PORT` | hardcoded `5432` |
| `DB_IDENTITY_NAME` / `_USERNAME` / `_PASSWORD` | `terraform output` |
| `DB_WEBMODELER_NAME` / `_USERNAME` / `_PASSWORD` | `terraform output` |

### 3.7 Install Camunda

```bash
helm upgrade --install "$CAMUNDA_RELEASE_NAME" \
  oci://registry.camunda.cloud/team-distribution/camunda-platform \
  --version "$CAMUNDA_HELM_CHART_VERSION" \
  --namespace "$CAMUNDA_NAMESPACE" \
  -f generated-values.yml
```

> The OCI registry `registry.camunda.cloud/team-distribution/camunda-platform` does not require authentication for public chart versions and dev-latest tags.

---

## Verification

```bash
# All pods running
kubectl get pods -n camunda

# TLS certificates issued
kubectl get certificate -n camunda

# Ingress has LB IP
kubectl get ingress -n camunda

# DNS resolves to LB
dig +short camunda.<your-prefix>.azure.camunda.ie

# Keycloak OIDC endpoint reachable
curl -sI https://camunda.<your-prefix>.azure.camunda.ie/auth/realms/camunda-platform/.well-known/openid-configuration

# Camunda UI redirects to OIDC
curl -sI https://camunda.<your-prefix>.azure.camunda.ie | head -3
```

Expected: `HTTP/2 302` redirect to `/oauth2/authorization/oidc`.

Keycloak admin credentials (for Keycloak UI / realm inspection):

```bash
kubectl get secret keycloak-initial-admin -n camunda \
  -o go-template='username: {{index .data "username" | base64decode}}{{"\n"}}password: {{index .data "password" | base64decode}}{{"\n"}}'
```

---

## Teardown

```bash
# Remove Helm release and operators
helm uninstall camunda -n camunda
kubectl delete namespace camunda elastic-system cnpg-system

# Destroy infrastructure (from the aks-single-region dir)
source .env.local
terraform destroy
```

If Key Vault soft-delete blocks re-deployment with the same prefix, purge it:

```bash
az keyvault list-deleted --query "[].{name:name, location:properties.location}" -o table
az keyvault purge --name <name> --location <location>
```

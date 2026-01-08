# aks

> **Note**: This reference architecture uses:
> - **EntraID** for authentication (instead of Keycloak) - **automatically configured via Terraform**
> - **ECK Operator** for Elasticsearch management
> - **External PostgreSQL** for Identity and WebModeler databases

## Prerequisites

### Azure Credentials

You need Azure credentials with permissions to:
- Create resource groups, networks, AKS clusters, and PostgreSQL databases
- Create Azure AD / EntraID application registrations

Set these environment variables:
```bash
export ARM_CLIENT_ID="your-client-id"
export ARM_CLIENT_SECRET="your-client-secret"
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"
```

## Deployment Steps

### 1. Deploy Infrastructure with EntraID Configuration

Terraform will automatically create:
- AKS cluster and networking
- PostgreSQL database
- **EntraID application registrations** for all Camunda components

```bash
# Initialize Terraform
terraform init

# Optional: Set domain name for production deployment
# Leave empty for localhost/port-forwarding setup
cat > terraform.tfvars <<EOF
subscription_id = "your-subscription-id"
terraform_sp_app_id = "your-terraform-sp-app-id"
domain_name = "camunda.yourdomain.com"  # or leave as "" for localhost
enable_webmodeler = false  # set to true if you want WebModeler
EOF

# Deploy infrastructure
terraform apply
```

### 2. Export Database Variables

```bash
cd procedure
source ./vars-create-db.sh
```

### 3. Create Database

```bash
./create-setup-db-secret.sh
kubectl apply -f ../manifests/setup-postgres-create-db.yml -n camunda
```

### 4. Deploy Elasticsearch (ECK Operator)

```bash
./deploy-elasticsearch.sh
```

### 5. Export EntraID Variables and Create Secrets

```bash
# Export EntraID credentials from Terraform
source ./export-entraid-vars.sh

# Create database secrets
./create-external-db-secrets.sh

# Create EntraID secrets (optional, values are used directly in helm via env vars)
./create-entraid-secrets.sh
```

### 6. Deploy Camunda

```bash
# Get domain name from terraform (if configured)
export DOMAIN_NAME=$(terraform output -raw domain_name 2>/dev/null || echo "")

# Substitute environment variables in helm values
if [ -n "$DOMAIN_NAME" ]; then
    # For domain setup
    envsubst < ../helm-values/values-domain.yml | helm install camunda camunda/camunda-platform \
      -f - \
      --namespace camunda
else
    # For no-domain setup
    envsubst < ../helm-values/values-no-domain.yml | helm install camunda camunda/camunda-platform \
      -f - \
      --namespace camunda
fi
```

## Architecture Notes

### EntraID Integration

Terraform automatically creates the following Azure AD application registrations:
- **Identity** (`camunda-identity`) - Identity management and admin console
- **Optimize** (`camunda-optimize`) - Process optimization and analytics
- **Operate** (`camunda-operate`) - Process instance management
- **Tasklist** (`camunda-tasklist`) - User task management
- **Console** (`camunda-console`) - Management console
- **WebModeler** (`camunda-webmodeler`) - Optional, if `enable_webmodeler = true`

Each application is configured with:
- Proper redirect URIs (domain-based or localhost)
- Client secrets stored in Terraform state
- Microsoft Graph API permissions (User.Read)

### Security Considerations

- **Client Secrets**: Stored in Terraform state - ensure state is encrypted and access-controlled
- **Outputs**: Sensitive values are marked as sensitive in Terraform
- **Kubernetes Secrets**: EntraID credentials can be stored in k8s secrets or passed via environment variables

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_aks"></a> [aks](#module\_aks) | ../../modules/aks | n/a |
| <a name="module_kms"></a> [kms](#module\_kms) | ../../modules/kms | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../../modules/network | n/a |
| <a name="module_postgres_db"></a> [postgres\_db](#module\_postgres\_db) | ../../modules/postgres-db | n/a |
## Resources

| Name | Type |
|------|------|
| [azuread_application.console](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application.identity](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application.optimize](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application.orchestration](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application.webmodeler_api](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application.webmodeler_ui](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_password.identity](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_application_password.optimize](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_application_password.orchestration](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_application_password.webmodeler_api](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azurerm_resource_group.app_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aks_dns_service_ip"></a> [aks\_dns\_service\_ip](#input\_aks\_dns\_service\_ip) | IP address within the service CIDR that will be used for DNS | `string` | `"10.0.0.10"` | no |
| <a name="input_aks_network_plugin"></a> [aks\_network\_plugin](#input\_aks\_network\_plugin) | Network plugin to use for Kubernetes networking | `string` | `"azure"` | no |
| <a name="input_aks_network_policy"></a> [aks\_network\_policy](#input\_aks\_network\_policy) | Network policy to use for Kubernetes networking | `string` | `"calico"` | no |
| <a name="input_aks_pod_cidr"></a> [aks\_pod\_cidr](#input\_aks\_pod\_cidr) | CIDR block for pod IP addresses (only used with kubenet) | `string` | `"10.244.0.0/16"` | no |
| <a name="input_aks_service_cidr"></a> [aks\_service\_cidr](#input\_aks\_service\_cidr) | CIDR block for Kubernetes service IP addresses | `string` | `"10.0.0.0/16"` | no |
| <a name="input_aks_subnet_address_prefix"></a> [aks\_subnet\_address\_prefix](#input\_aks\_subnet\_address\_prefix) | Address prefix for the AKS subnet | `list(string)` | <pre>[<br/>  "10.1.0.0/24"<br/>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Optional override for the AKS cluster name | `string` | `""` | no |
| <a name="input_db_subnet_address_prefix"></a> [db\_subnet\_address\_prefix](#input\_db\_subnet\_address\_prefix) | Address prefix for the database subnet | `list(string)` | <pre>[<br/>  "10.1.1.0/24"<br/>]</pre> | no |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Azure Resource ID of the shared DNS zone | `string` | `null` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name for Camunda deployment (leave empty for localhost/port-forwarding setup) | `string` | `""` | no |
| <a name="input_enable_webmodeler"></a> [enable\_webmodeler](#input\_enable\_webmodeler) | Enable WebModeler component and create EntraID app registration | `bool` | `false` | no |
| <a name="input_identity_initial_user_email"></a> [identity\_initial\_user\_email](#input\_identity\_initial\_user\_email) | Email address of the initial admin user for Identity (must match preferred\_username claim in EntraID) | `string` | `"admin@example.com"` | no |
| <a name="input_pe_subnet_address_prefix"></a> [pe\_subnet\_address\_prefix](#input\_pe\_subnet\_address\_prefix) | Address prefix for the private endpoint subnet | `list(string)` | <pre>[<br/>  "10.1.2.0/24"<br/>]</pre> | no |
| <a name="input_postgres_backup_retention_days"></a> [postgres\_backup\_retention\_days](#input\_postgres\_backup\_retention\_days) | Backup retention days for PostgreSQL | `number` | `7` | no |
| <a name="input_postgres_enable_geo_redundant_backup"></a> [postgres\_enable\_geo\_redundant\_backup](#input\_postgres\_enable\_geo\_redundant\_backup) | Enable geo-redundant backup for PostgreSQL | `bool` | `true` | no |
| <a name="input_postgres_sku_tier"></a> [postgres\_sku\_tier](#input\_postgres\_sku\_tier) | SKU tier for PostgreSQL Flexible Server | `string` | `"GP_Standard_D2s_v3"` | no |
| <a name="input_postgres_standby_zone"></a> [postgres\_standby\_zone](#input\_postgres\_standby\_zone) | Standby Availability Zone for PostgreSQL high availability | `string` | `"2"` | no |
| <a name="input_postgres_storage_mb"></a> [postgres\_storage\_mb](#input\_postgres\_storage\_mb) | Storage size in MB for PostgreSQL | `number` | `32768` | no |
| <a name="input_postgres_version"></a> [postgres\_version](#input\_postgres\_version) | PostgreSQL version | `string` | `"15"` | no |
| <a name="input_postgres_zone"></a> [postgres\_zone](#input\_postgres\_zone) | Primary Availability Zone for PostgreSQL server | `string` | `"1"` | no |
| <a name="input_resource_prefix_placeholder"></a> [resource\_prefix\_placeholder](#input\_resource\_prefix\_placeholder) | Placeholder for the resource prefix | `string` | `""` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | The Azure Subscription ID to deploy into | `string` | n/a | yes |
| <a name="input_system_node_pool_count"></a> [system\_node\_pool\_count](#input\_system\_node\_pool\_count) | Number of nodes in the system node pool | `number` | `1` | no |
| <a name="input_system_node_pool_vm_size"></a> [system\_node\_pool\_vm\_size](#input\_system\_node\_pool\_vm\_size) | VM size for the system node pool | `string` | `"Standard_D2s_v3"` | no |
| <a name="input_system_node_pool_zones"></a> [system\_node\_pool\_zones](#input\_system\_node\_pool\_zones) | List of AZs for the system node pool | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | <pre>{<br/>  "Environment": "Testing",<br/>  "Purpose": "Reference Implementation"<br/>}</pre> | no |
| <a name="input_terraform_sp_app_id"></a> [terraform\_sp\_app\_id](#input\_terraform\_sp\_app\_id) | The Service Principals Application (client) ID that Terraform is using | `string` | n/a | yes |
| <a name="input_user_node_pool_count"></a> [user\_node\_pool\_count](#input\_user\_node\_pool\_count) | Number of nodes in the user node pool | `number` | `5` | no |
| <a name="input_user_node_pool_vm_size"></a> [user\_node\_pool\_vm\_size](#input\_user\_node\_pool\_vm\_size) | VM size for the user node pool | `string` | `"Standard_D4s_v3"` | no |
| <a name="input_user_node_pool_zones"></a> [user\_node\_pool\_zones](#input\_user\_node\_pool\_zones) | List of AZs for the user node pool | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Address space for the virtual network | `list(string)` | <pre>[<br/>  "10.1.0.0/16"<br/>]</pre> | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aks_cluster_id"></a> [aks\_cluster\_id](#output\_aks\_cluster\_id) | ID of the deployed AKS cluster |
| <a name="output_aks_cluster_name"></a> [aks\_cluster\_name](#output\_aks\_cluster\_name) | Name of the AKS cluster |
| <a name="output_aks_fqdn"></a> [aks\_fqdn](#output\_aks\_fqdn) | FQDN of the AKS cluster |
| <a name="output_azure_tenant_id"></a> [azure\_tenant\_id](#output\_azure\_tenant\_id) | Azure AD Tenant ID |
| <a name="output_camunda_database_identity"></a> [camunda\_database\_identity](#output\_camunda\_database\_identity) | n/a |
| <a name="output_camunda_database_webmodeler"></a> [camunda\_database\_webmodeler](#output\_camunda\_database\_webmodeler) | n/a |
| <a name="output_camunda_identity_db_password"></a> [camunda\_identity\_db\_password](#output\_camunda\_identity\_db\_password) | n/a |
| <a name="output_camunda_identity_db_username"></a> [camunda\_identity\_db\_username](#output\_camunda\_identity\_db\_username) | n/a |
| <a name="output_camunda_webmodeler_db_password"></a> [camunda\_webmodeler\_db\_password](#output\_camunda\_webmodeler\_db\_password) | n/a |
| <a name="output_camunda_webmodeler_db_username"></a> [camunda\_webmodeler\_db\_username](#output\_camunda\_webmodeler\_db\_username) | n/a |
| <a name="output_console_audience"></a> [console\_audience](#output\_console\_audience) | Console Application ID URI |
| <a name="output_console_client_id"></a> [console\_client\_id](#output\_console\_client\_id) | Console Application (client) ID |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | Domain name for Camunda deployment |
| <a name="output_identity_audience"></a> [identity\_audience](#output\_identity\_audience) | Identity Application ID URI |
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Identity Application (client) ID |
| <a name="output_identity_client_secret"></a> [identity\_client\_secret](#output\_identity\_client\_secret) | Identity Client Secret |
| <a name="output_identity_initial_user_email"></a> [identity\_initial\_user\_email](#output\_identity\_initial\_user\_email) | Email of the initial admin user for Identity |
| <a name="output_optimize_audience"></a> [optimize\_audience](#output\_optimize\_audience) | Optimize Application ID URI |
| <a name="output_optimize_client_id"></a> [optimize\_client\_id](#output\_optimize\_client\_id) | Optimize Application (client) ID |
| <a name="output_optimize_client_secret"></a> [optimize\_client\_secret](#output\_optimize\_client\_secret) | Optimize Client Secret |
| <a name="output_orchestration_audience"></a> [orchestration\_audience](#output\_orchestration\_audience) | Orchestration Cluster Application ID URI |
| <a name="output_orchestration_client_id"></a> [orchestration\_client\_id](#output\_orchestration\_client\_id) | Orchestration Cluster Application (client) ID |
| <a name="output_orchestration_client_secret"></a> [orchestration\_client\_secret](#output\_orchestration\_client\_secret) | Orchestration Cluster Client Secret |
| <a name="output_postgres_admin_password"></a> [postgres\_admin\_password](#output\_postgres\_admin\_password) | PostgreSQL admin password |
| <a name="output_postgres_admin_username"></a> [postgres\_admin\_username](#output\_postgres\_admin\_username) | PostgreSQL admin user |
| <a name="output_postgres_fqdn"></a> [postgres\_fqdn](#output\_postgres\_fqdn) | The fully qualified domain name of the PostgreSQL Flexible Server |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group |
| <a name="output_webmodeler_api_audience"></a> [webmodeler\_api\_audience](#output\_webmodeler\_api\_audience) | WebModeler API Application ID URI |
| <a name="output_webmodeler_api_client_id"></a> [webmodeler\_api\_client\_id](#output\_webmodeler\_api\_client\_id) | WebModeler API Application (client) ID |
| <a name="output_webmodeler_api_client_secret"></a> [webmodeler\_api\_client\_secret](#output\_webmodeler\_api\_client\_secret) | WebModeler API Client Secret |
| <a name="output_webmodeler_ui_audience"></a> [webmodeler\_ui\_audience](#output\_webmodeler\_ui\_audience) | WebModeler UI Application ID URI |
| <a name="output_webmodeler_ui_client_id"></a> [webmodeler\_ui\_client\_id](#output\_webmodeler\_ui\_client\_id) | WebModeler UI Application (client) ID |
<!-- END_TF_DOCS -->

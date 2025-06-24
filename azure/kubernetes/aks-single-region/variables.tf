# Network configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for the AKS subnet"
  type        = list(string)
  default     = ["10.1.0.0/24"]
}

variable "db_subnet_address_prefix" {
  description = "Address prefix for the database subnet"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

# AKS network configuration
variable "aks_network_plugin" {
  description = "Network plugin to use for Kubernetes networking"
  type        = string
  default     = "azure" # "azure" or "kubenet"
}

variable "aks_network_policy" {
  description = "Network policy to use for Kubernetes networking"
  type        = string
  default     = "calico" # "calico" or "azure"
}

variable "aks_pod_cidr" {
  description = "CIDR block for pod IP addresses (only used with kubenet)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "aks_service_cidr" {
  description = "CIDR block for Kubernetes service IP addresses"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "IP address within the service CIDR that will be used for DNS"
  type        = string
  default     = "10.0.0.10"
}

variable "pe_subnet_address_prefix" {
  description = "Address prefix for the private endpoint subnet"
  type        = list(string)
  default     = ["10.1.2.0/24"]
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Environment = "Testing"
    Purpose     = "Reference Implementation"
  }
}

# AKS module specific variables
variable "cluster_name" {
  description = "Optional override for the AKS cluster name"
  type        = string
  default     = ""
}

variable "system_node_pool_count" {
  description = "Number of nodes in the system node pool"
  type        = number
  default     = 1
}

variable "system_node_pool_vm_size" {
  description = "VM size for the system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "user_node_pool_count" {
  description = "Number of nodes in the user node pool"
  type        = number
  default     = 5
}

variable "user_node_pool_vm_size" {
  description = "VM size for the user node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "system_node_pool_zones" {
  description = "List of AZs for the system node pool"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "user_node_pool_zones" {
  description = "List of AZs for the user node pool"
  type        = list(string)
  default     = ["1", "2", "3"]
}

# PostgreSQL Variables
variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "postgres_sku_tier" {
  description = "SKU tier for PostgreSQL Flexible Server"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "postgres_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 32768
}

variable "postgres_backup_retention_days" {
  description = "Backup retention days for PostgreSQL"
  type        = number
  default     = 7
}

variable "postgres_enable_geo_redundant_backup" {
  description = "Enable geo-redundant backup for PostgreSQL"
  type        = bool
  default     = true # Enabled for production reference architecture
}

variable "postgres_zone" {
  description = "Primary Availability Zone for PostgreSQL server"
  type        = string
  default     = "1"
}

variable "postgres_standby_zone" {
  description = "Standby Availability Zone for PostgreSQL high availability"
  type        = string
  default     = "2"
  # Must be different from primary zone for zone-redundant high availability
}

variable "subscription_id" {
  description = "The Azure Subscription ID to deploy into"
  type        = string
}

variable "terraform_sp_app_id" {
  type        = string
  description = "The Service Principals Application (client) ID that Terraform is using"
}

variable "resource_prefix_placeholder" {
  description = "Placeholder for the resource prefix"
  type        = string
  default     = ""
}

variable "dns_zone_id" {
  description = "Azure Resource ID of the shared DNS zone"
  type        = string
  default     = null
}

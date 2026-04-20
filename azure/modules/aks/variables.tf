variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "location" {
  description = "Region where the AKS cluster will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the AKS cluster will be deployed"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the AKS cluster"
  type        = string
  # renovate: datasource=endoflife-date depName=azure-kubernetes-service versioning=loose
  default = "1.34"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# System node pool configuration
variable "system_node_pool_vm_size" {
  description = "VM size for the system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_disk_size_gb" {
  description = "OS disk size in GB for system nodes"
  type        = number
  default     = 30
}

variable "system_node_pool_count" {
  description = "Number of nodes in the system node pool"
  type        = number
  default     = 3
}

# User node pool configuration
variable "user_node_pool_vm_size" {
  description = "VM size for the user node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "user_node_disk_size_gb" {
  description = "OS disk size in GB for user nodes"
  type        = number
  default     = 30
}

variable "user_node_pool_count" {
  description = "Number of nodes in the user node pool"
  type        = number
  default     = 2
}

variable "user_node_pool_drain_timeout_in_minutes" {
  description = "The amount of time in minutes to wait on eviction of pods and graceful termination per node"
  type        = number
  default     = 0
}

variable "user_node_pool_max_surge" {
  description = "The maximum number or percentage of nodes which will be added to the Node Pool size during an upgrade"
  type        = number
  default     = 10
}

variable "user_node_pool_node_soak_duration_in_minutes" {
  description = "The amount of time in minutes to wait after draining a node and before reimaging and moving on to next node"
  type        = number
  default     = 0
}

# Network configuration
variable "network_plugin" {
  description = "Network plugin to use for Kubernetes networking"
  type        = string
  default     = "azure"
}

variable "network_policy" {
  description = "Network policy to use for Kubernetes networking"
  type        = string
  default     = "calico"
}

variable "pod_cidr" {
  description = "CIDR block for pod IP addresses"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes service IP addresses"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address within the service CIDR that will be used for DNS"
  type        = string
  default     = "10.0.0.10"
}

variable "pe_subnet_address_prefix" {
  description = "Address prefix for the private endpoint subnet"
  type        = list(string)
  default     = ["10.1.2.0/24"]
}

variable "system_node_pool_zones" {
  type        = list(string)
  description = "AZs for system node pool, e.g. [\"1\",\"2\",\"3\"]"
  default     = ["1", "2", "3"]
}

variable "user_node_pool_zones" {
  type        = list(string)
  description = "AZs for user node pool"
  default     = ["1", "2", "3"]
}

variable "uami_id" {
  type        = string
  description = "User-assigned identity ID to use for KMS"
}

variable "uami_object_id" {
  type        = string
  description = "User-assigned identity object ID to use for KMS"
}

variable "kms_key_id" {
  type        = string
  description = "Key Vault Key ID for envelope-encryption"
}

variable "dns_zone_id" {
  description = "The Azure DNS zone resource id for ExternalDNS or cert-manager"
  type        = string
  default     = null
}

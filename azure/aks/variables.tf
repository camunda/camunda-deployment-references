variable "location" {
  description = "Region where resources will be deployed"
  type        = string
  default     = "swedencentral"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "camunda-rg"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "camunda-aks"
}


variable "node_pool_count" {
  description = "Fixed number of nodes in the default node pool"
  type        = number
  default     = 3
}

variable "api_private_access" {
  description = "Enable private API access for AKS"
  type        = bool
  default     = true
}

variable "private_dns_zone_id" {
  description = "Private DNS Zone ID for AKS API Server"
  type        = string
  default     = null
}

variable "api_allowed_ip_ranges" {
  description = "List of allowed IP ranges for public API access"
  type        = list(string)
  default     = []
}

variable "admin_group_object_id" {
  description = "Microsoft Entra ID group for Kubernetes admins"
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

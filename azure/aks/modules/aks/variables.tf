variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "camunda-aks"
}

variable "location" {
  description = "Region where the AKS cluster will be deployed"
  type        = string
  default     = "swedencentral"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the AKS cluster will be deployed"
  type        = string
}

variable "node_pool_count" {
  description = "Fixed number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to AKS cluster"
  type        = map(string)
  default     = {}
}

variable "node_vm_size" {
  description = "VM size for AKS node pool"
  type        = string
  default     = "standard_d2_v2"
}

variable "node_disk_size_gb" {
  description = "OS disk size in GB for AKS nodes"
  type        = number
  default     = 30
}

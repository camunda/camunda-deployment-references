variable "resource_group_name" {
  type        = string
  description = "Name of the Resource Group to house Key Vault & UAMI"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "kv_name" {
  type        = string
  description = "Name for the Key Vault"
}

variable "key_name" {
  type        = string
  description = "Name for the key inside Key Vault"
}

variable "uai_name" {
  type        = string
  description = "Name for the User-Assigned Managed Identity"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "terraform_sp_app_id" {
  type        = string
  description = "The Service Principal’s Application (client) ID that Terraform is using"
}

variable "aks_subnet_id" {
  type        = string
  description = "The subnet ID for the AKS cluster"
}

variable "api_server_subnet_id" {
  description = "The subnet ID to use for AKS API-server VNet integration"
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "The ID of the subnet where the private endpoint will be created"
  type        = string
}

variable "keyvault_private_dns_zone_id" {
  description = "The ID of the private DNS zone for Key Vault"
  type        = string
}

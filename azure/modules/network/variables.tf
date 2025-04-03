variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Region where resources will be deployed"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "camunda"
}

variable "nsg_name" {
  description = "Name of the Network Security Group"
  type        = string
  default     = "camunda-aks-nsg"
}

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

variable "api_server_authorized_ranges" {
  description = "CIDR ranges authorized to access the Kubernetes API server"
  type        = string
  default     = "*" # Allow all for testing, but in production use specific CIDR ranges
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "pe_subnet_address_prefix" {
  description = "Address prefix for the private endpoint subnet"
  type        = list(string)
  default     = ["10.1.2.0/24"]
}

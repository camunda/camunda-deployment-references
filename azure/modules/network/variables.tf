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

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

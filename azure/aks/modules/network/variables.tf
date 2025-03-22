variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Region where resources will be deployed"
  type        = string
}

variable "nsg_name" {
  description = "Name of the Network Security Group"
  type        = string
  default     = "camunda-aks-nsg"
}

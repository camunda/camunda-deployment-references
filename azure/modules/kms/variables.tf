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

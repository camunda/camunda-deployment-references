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

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "camunda"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Environment = "Testing"
    Purpose     = "Reference Implementation"
  }
}

# AKS Variables

variable "kubernetes_version" {
  description = "Kubernetes version to use for the AKS cluster"
  type        = string
  default     = "1.32.0"
}

# PostgreSQL Variables
variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

variable "db_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "pgadmin"
}

variable "db_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  default     = "P@ssw0rd1234!" # FOR TESTING ONLY - not for production
  sensitive   = true
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
  default     = true
}

variable "postgres_zone" {
  description = "Primary Availability Zone for PostgreSQL"
  type        = string
  default     = "1"
}

variable "postgres_standby_zone" {
  description = "Standby Availability Zone for PostgreSQL"
  type        = string
  default     = "2"
}

# Database Definitions - Split into non-sensitive data and sensitive passwords
variable "databases" {
  description = "Map of database configurations (non-sensitive)"
  type = map(object({
    name     = string
    username = string
  }))
  default = {
    keycloak = {
      name     = "camunda_keycloak"
      username = "keycloak_user"
    },
    identity = {
      name     = "camunda_identity"
      username = "identity_user"
    },
    webmodeler = {
      name     = "camunda_webmodeler"
      username = "webmodeler_user"
    }
  }
}

# Store passwords separately to avoid for_each with sensitive values
variable "database_passwords" {
  description = "Map of database passwords (sensitive)"
  type        = map(string)
  default = {
    keycloak   = "Keycloak1234!"   # FOR TESTING ONLY
    identity   = "Identity1234!"   # FOR TESTING ONLY
    webmodeler = "Webmodeler1234!" # FOR TESTING ONLY
  }
  sensitive = true
}

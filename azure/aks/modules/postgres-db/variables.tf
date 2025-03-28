variable "resource_group_name" {
  description = "Resource group name for PostgreSQL Flexible Server"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "server_name" {
  description = "Name for the PostgreSQL Flexible Server instance"
  type        = string
}

variable "admin_username" {
  description = "Administrator login name for PostgreSQL Flexible Server"
  type        = string
}

variable "admin_password" {
  description = "Administrator password for PostgreSQL Flexible Server"
  type        = string
  sensitive   = true
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "sku_tier" {
  description = "SKU name for the PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "Backup retention period in days (7-35)"
  type        = number
  default     = 7
}

variable "enable_geo_redundant_backup" {
  description = "Enable geo-redundant backup"
  type        = bool
  default     = false # Disabled for testing to save costs
}

variable "zone" {
  description = "Primary Availability Zone for the PostgreSQL server"
  type        = string
  default     = "1"
}

variable "standby_availability_zone" {
  description = "Availability Zone for the standby instance (must differ from primary)"
  type        = string
  default     = "2"
}

# Simplified database configurations using map for better organization
# Non-sensitive information only
variable "databases" {
  description = "Map of database configurations (non-sensitive information)"
  type = map(object({
    name     = string
    username = string
  }))
}

# Store passwords separately to avoid for_each with sensitive values
variable "database_passwords" {
  description = "Map of database passwords (sensitive)"
  type        = map(string)
  sensitive   = true
}

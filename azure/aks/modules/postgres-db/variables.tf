variable "resource_group_name" {
  description = "Resource group name for PostgreSQL Flexible Server"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
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
  description = "SKU name for the PostgreSQL Flexible Server (e.g., GP_Standard_D2s_v3 or MO_Standard_E4s_v3)"
  type        = string
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
  default     = true
}

variable "delegated_subnet_id" {
  description = "ID of the subnet delegated to PostgreSQL Flexible Server (from your networking module)"
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the Private DNS Zone for PostgreSQL Flexible Server (from your networking module)"
  type        = string
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

# Database names
variable "db_keycloak_name" {
  description = "Name of the Camunda Keycloak database"
  type        = string
  default     = "camunda_keycloak"
}

variable "db_identity_name" {
  description = "Name of the Camunda Identity database"
  type        = string
  default     = "camunda_identity"
}

variable "db_webmodeler_name" {
  description = "Name of the Camunda WebModeler database"
  type        = string
  default     = "camunda_webmodeler"
}

# Connection credentials for each database
variable "db_keycloak_username" {
  description = "Connection username for the Keycloak database"
  type        = string
  default     = "keycloak_db"
}

variable "db_identity_username" {
  description = "Connection username for the Identity database"
  type        = string
  default     = "identity_db"
}

variable "db_webmodeler_username" {
  description = "Connection username for the WebModeler database"
  type        = string
  default     = "webmodeler_db"
}

variable "db_keycloak_password" {
  description = "Connection password for the Keycloak database"
  type        = string
  default     = "secretvalue%24"
  sensitive   = true
}

variable "db_identity_password" {
  description = "Connection password for the Identity database"
  type        = string
  default     = "secretvalue%25"
  sensitive   = true
}

variable "db_webmodeler_password" {
  description = "Connection password for the WebModeler database"
  type        = string
  default     = "secretvalue%26"
  sensitive   = true
}

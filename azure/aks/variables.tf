variable "postgres_server_name" {
  description = "Name of the PostgreSQL Flexible Server instance"
  type        = string
  default     = "cluster-name-pg-std"
}

variable "db_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "secret_user"
}

variable "db_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  default     = "secretvalue%23"
  sensitive   = true
}

variable "postgres_sku_tier" {
  description = "SKU tier for PostgreSQL Flexible Server (e.g., GP_Standard_D2s_v3)"
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

variable "db_keycloak_username" {
  description = "Username for the Camunda Keycloak database connection"
  type        = string
  default     = "keycloak_db"
}

variable "db_identity_username" {
  description = "Username for the Camunda Identity database connection"
  type        = string
  default     = "identity_db"
}

variable "db_webmodeler_username" {
  description = "Username for the Camunda WebModeler database connection"
  type        = string
  default     = "webmodeler_db"
}

variable "db_keycloak_password" {
  description = "Password for the Camunda Keycloak database connection"
  type        = string
  default     = "secretvalue%24"
  sensitive   = true
}

variable "db_identity_password" {
  description = "Password for the Camunda Identity database connection"
  type        = string
  default     = "secretvalue%25"
  sensitive   = true
}

variable "db_webmodeler_password" {
  description = "Password for the Camunda WebModeler database connection"
  type        = string
  default     = "secretvalue%26"
  sensitive   = true
}
variable "postgres_server_name" {
  description = "Name of the PostgreSQL Flexible Server instance"
  type        = string
  default     = "cluster-name-pg-std"
}

variable "db_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "secret_user"
}

variable "db_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  default     = "secretvalue%23"
  sensitive   = true
}

variable "postgres_sku_tier" {
  description = "SKU tier for PostgreSQL Flexible Server (e.g., GP_Standard_D2s_v3)"
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

variable "db_keycloak_username" {
  description = "Username for the Camunda Keycloak database connection"
  type        = string
  default     = "keycloak_db"
}

variable "db_identity_username" {
  description = "Username for the Camunda Identity database connection"
  type        = string
  default     = "identity_db"
}

variable "db_webmodeler_username" {
  description = "Username for the Camunda WebModeler database connection"
  type        = string
  default     = "webmodeler_db"
}

variable "db_keycloak_password" {
  description = "Password for the Camunda Keycloak database connection"
  type        = string
  default     = "secretvalue%24"
  sensitive   = true
}

variable "db_identity_password" {
  description = "Password for the Camunda Identity database connection"
  type        = string
  default     = "secretvalue%25"
  sensitive   = true
}

variable "db_webmodeler_password" {
  description = "Password for the Camunda WebModeler database connection"
  type        = string
  default     = "secretvalue%26"
  sensitive   = true
}

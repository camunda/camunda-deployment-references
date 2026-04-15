variable "global_cluster_identifier" {
  type        = string
  description = "Identifier for the Aurora Global Database cluster"
}

variable "engine" {
  type        = string
  default     = "aurora-postgresql"
  description = "The engine type e.g. aurora-postgresql"
}

variable "engine_version" {
  type = string
  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  default     = "17.9"
  description = "The DB engine version for Postgres to use"
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "If true, minor engine upgrades are applied automatically"
}

variable "database_name" {
  type        = string
  default     = "camunda"
  description = "The name for the automatically created database"
}

variable "master_username" {
  type        = string
  description = "The username for the postgres admin user"
  sensitive   = true
}

variable "master_password" {
  type        = string
  description = "The password for the postgres admin user"
  sensitive   = true
}

variable "iam_auth_enabled" {
  type        = bool
  default     = true
  description = "Enable IAM database authentication"
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain automated Aurora backups. Minimum 1; set higher for production. Defaults to 7 to give a reasonable recovery window for dual-region failover scenarios."
}

variable "instance_class" {
  type        = string
  default     = "db.r6g.large"
  description = "The instance type of the Aurora instances"
}

variable "ca_cert_identifier" {
  type        = string
  default     = "rds-ca-rsa2048-g1"
  description = "CA certificate identifier for DB instances"
}

################################################################
#                    Primary Cluster (Region 0)                #
################################################################

variable "primary_cluster_name" {
  type        = string
  description = "Identifier for the primary Aurora cluster"
}

variable "primary_vpc_id" {
  type        = string
  description = "VPC ID for the primary cluster"
}

variable "primary_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the primary cluster"
}

variable "primary_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks to allow access from/to the primary cluster"
}

variable "primary_availability_zones" {
  type        = list(string)
  description = "Availability zones for the primary cluster"
}

variable "primary_num_instances" {
  type        = number
  default     = 1
  description = "Number of instances in the primary cluster"
}

################################################################
#                   Secondary Cluster (Region 1)               #
################################################################

variable "secondary_cluster_name" {
  type        = string
  description = "Identifier for the secondary Aurora cluster"
}

variable "secondary_vpc_id" {
  type        = string
  description = "VPC ID for the secondary cluster"
}

variable "secondary_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the secondary cluster"
}

variable "secondary_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks to allow access from/to the secondary cluster"
}

variable "secondary_num_instances" {
  type        = number
  default     = 1
  description = "Number of instances in the secondary cluster"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to add to resources"
}

variable "cluster_identifier" {
  description = "Identifier of the regional Aurora cluster. Lowercase letters, digits and hyphens, starting with a letter and not ending with one."
  type        = string
}

variable "global_cluster_identifier" {
  description = "ID of the aws_rds_global_cluster this regional cluster joins"
  type        = string
}

variable "is_primary" {
  description = "Whether this member is the writer (primary) of the global cluster. Exactly one member must set this to true."
  type        = bool
  default     = false
}

variable "engine" {
  description = "Aurora engine type. Only aurora-postgresql is exercised by the reference architecture."
  type        = string
  default     = "aurora-postgresql"
}

variable "engine_version" {
  description = "Aurora engine version. Must match the version of the global cluster."
  type        = string
  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  default = "17.9"
}

variable "auto_minor_version_upgrade" {
  description = "Whether minor engine upgrades are applied automatically during the maintenance window"
  type        = bool
  default     = true
}

variable "instance_class" {
  description = "Instance class of the Aurora cluster instances"
  type        = string
  default     = "db.r6g.large"
}

variable "num_instances" {
  description = "Number of Aurora instances in this region. Use at least 2 in production for intra-region failover."
  type        = number
  default     = 1
}

variable "database_name" {
  description = "Name of the initial database. Only honoured on the primary member."
  type        = string
  default     = "camunda"
}

variable "master_username" {
  description = "Master username. Only honoured on the primary member."
  type        = string
  sensitive   = true
  default     = null
}

variable "master_password" {
  description = "Master password. Only honoured on the primary member."
  type        = string
  sensitive   = true
  default     = null
}

variable "availability_zones" {
  description = "Availability zones of the regional cluster. Only honoured on the primary member."
  type        = list(string)
  default     = null
}

variable "vpc_id" {
  description = "ID of the VPC the Aurora security group is created in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs used for the Aurora DB subnet group"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the database. Must contain every participating region VPC CIDR, because brokers in any region connect to the current global writer."
  type        = list(string)
}

variable "port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "iam_auth_enabled" {
  description = "Whether IAM database authentication is enabled. Recommended: the AWS JDBC wrapper iam plugin removes the need to distribute a password."
  type        = bool
  default     = true
}

variable "ca_cert_identifier" {
  description = "Certificate authority used by the cluster instances"
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

variable "backup_retention_period" {
  description = "Number of days automated backups are retained"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Whether the final snapshot is skipped on destroy. Kept true for the reference architecture, which is disposable."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Whether modifications are applied immediately instead of during the maintenance window"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource created by this module"
  type        = map(string)
  default     = {}
}

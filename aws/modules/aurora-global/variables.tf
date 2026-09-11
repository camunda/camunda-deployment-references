variable "global_cluster_identifier" {
  type        = string
  description = "Identifier for the Aurora Global Database cluster"
}

variable "engine" {
  type        = string
  default     = "aurora-postgresql"
  description = "The Aurora engine type: 'aurora-postgresql' or 'aurora-mysql'"

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "engine must be either 'aurora-postgresql' or 'aurora-mysql'."
  }
}

# DEPRECATED. Removed as an input in favour of the per-engine pins below, which
# each carry their own Renovate annotation. Kept only so that a consumer still
# setting it gets an actionable message instead of Terraform's bare "An argument
# named engine_version is not expected here". Safe to delete once consumers have
# migrated.
variable "engine_version" {
  type        = string
  default     = null
  description = "DEPRECATED and non-functional. Use postgresql_engine_version or mysql_engine_version, whichever matches var.engine; the module selects between them."

  validation {
    condition     = var.engine_version == null
    error_message = "engine_version has been removed. Set postgresql_engine_version (when engine = aurora-postgresql) or mysql_engine_version (when engine = aurora-mysql) instead — the module selects the right one for the engine in use."
  }
}

variable "postgresql_engine_version" {
  type = string
  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  default     = "18.4"
  description = "Aurora PostgreSQL engine version, used when engine = aurora-postgresql. Set this to pin a specific version for the PostgreSQL path."
}

variable "mysql_engine_version" {
  type = string
  # Aurora MySQL versions are compound (8.4.mysql_aurora.8.4.7) and need a
  # regex versioning so Renovate orders them correctly. That versioning is
  # attached centrally to the custom.aurora-mysql-camunda datasource in
  # camunda/infraex-common-config (default.json5), so no inline `versioning=`
  # is needed here. See camunda/team-infrastructure-experience#1209.
  # renovate: datasource=custom.aurora-mysql-camunda depName=aurora-mysql
  default     = "8.4.mysql_aurora.8.4.7"
  description = "Aurora MySQL engine version, used when engine = aurora-mysql. Set this to pin a specific version for the MySQL path."
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
  description = "The username for the database admin user"
  sensitive   = true
}

variable "master_password" {
  type        = string
  description = "The password for the database admin user"
  sensitive   = true
}

variable "iam_auth_enabled" {
  type        = bool
  default     = true
  description = "Enable IAM database authentication"
}

variable "extra_wrapper_plugins" {
  type        = list(string)
  default     = []
  description = "Additional AWS Advanced JDBC Wrapper plugins to append to the jdbc_url. The module always sets 'failover' (and 'iam' when iam_auth_enabled), so list only the extras here, e.g. ['readWriteSplitting']. Duplicates of the built-in plugins are ignored. The position a plugin takes in the list is not the execution order: the wrapper re-sorts the pipeline by built-in weight unless autoSortWrapperPluginOrder is disabled, which extra_url_parameters must not do."

  validation {
    condition     = alltrue([for p in var.extra_wrapper_plugins : can(regex("^[A-Za-z][A-Za-z0-9]*$", p))])
    error_message = "extra_wrapper_plugins entries must be bare plugin codes (alphanumeric, no commas or spaces) — pass each plugin as its own list element."
  }
}

variable "extra_url_parameters" {
  type        = map(string)
  default     = {}
  description = "Additional query parameters appended to the jdbc_url, e.g. the failover plugin's { failoverTimeoutMs = \"60000\" } or the efm2 plugin's { failureDetectionTime = \"15000\" }. The parameters the module builds itself (wrapperPlugins, globalClusterInstanceHostPatterns, TLS mode) are reserved."

  # Two guards, both required. The shape check keeps '&' and '=' out of keys and
  # values, without which a single entry could append arbitrary extra parameters
  # to the URL (e.g. connectTimeout = "5000&wrapperPlugins=none") and defeat the
  # reserved-key check below. Rejecting is preferred over url-encoding: such
  # input can only be a mistake, and encoding would also mangle the ':' and '/'
  # that legitimately appear in values.
  validation {
    condition = alltrue([
      for k, v in var.extra_url_parameters :
      can(regex("^[A-Za-z][A-Za-z0-9]*$", k)) && can(regex("^[A-Za-z0-9._:/,-]+$", v))
    ])
    error_message = "extra_url_parameters keys must be bare JDBC parameter names (letters and digits, starting with a letter) and values may contain only letters, digits and . _ : / , - — notably no '&' or '=', so that no entry can append a parameter of its own."
  }

  # Compared lower-cased: the reserved list is a closed set of exact strings, so
  # a variant differing only in case (SSLMODE, wrapperplugins) would otherwise
  # slip through and land in the query string, where whether a driver honours it
  # is driver-specific — the same hazard as emitting a duplicate key. Folding
  # case also collapses the sslmode/sslMode pair (pgjdbc/Connector/J) to one
  # entry.
  validation {
    condition = length(setintersection(
      [for k in keys(var.extra_url_parameters) : lower(k)],
      ["wrapperplugins", "globalclusterinstancehostpatterns", "sslmode"],
    )) == 0
    error_message = "extra_url_parameters must not contain the parameters the module builds itself (wrapperPlugins, globalClusterInstanceHostPatterns, sslmode/sslMode), in any capitalisation — use extra_wrapper_plugins for the plugin list; the TLS mode and host patterns are not overridable."
  }
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

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain automated Aurora backups. Minimum 1; set higher for production. Defaults to 7 to give a reasonable recovery window for dual-region failover scenarios."
}

variable "skip_final_snapshot" {
  type        = bool
  default     = true
  description = "Whether to skip the final DB snapshot when the cluster is deleted. Set to false in production to retain a recovery point."
}

variable "apply_immediately" {
  type        = bool
  default     = true
  description = "Whether to apply cluster and instance changes immediately or during the next maintenance window."
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

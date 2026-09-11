################################
# Region Configuration        #
################################

variable "region_0" {
  type        = string
  default     = "eu-west-2"
  description = "AWS region for the primary (owner) cluster"
}

variable "region_1" {
  type        = string
  default     = "eu-west-3"
  description = "AWS region for the secondary (accepter) cluster"
}

################################################################
#                       VPC State Reference                     #
################################################################

variable "terraform_backend_bucket" {
  type        = string
  description = "S3 bucket name storing Terraform state for all layers"
}

variable "terraform_backend_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region of the S3 bucket storing Terraform state (may differ from the deployment regions)"
}

variable "terraform_backend_key_prefix" {
  type        = string
  description = "S3 key prefix shared by all layers. E.g. 'aws/containers/ecs-dual-region-fargate/my-cluster/' yields 's3://<bucket>/<prefix>vpc/terraform.tfstate'"
}

################################################################
#                   Secondary Storage Options                   #
################################################################

variable "secondary_storage_type" {
  type        = string
  default     = "rdbms"
  description = "Camunda secondary storage: 'rdbms' (Aurora Global) or 'opensearch'"

  validation {
    condition     = contains(["rdbms", "opensearch"], var.secondary_storage_type)
    error_message = "Must be 'rdbms' or 'opensearch'."
  }
}

variable "db_engine" {
  type        = string
  default     = "postgresql"
  description = "Aurora RDBMS engine for secondary storage: 'postgresql' or 'mysql'. Only applies when secondary_storage_type = 'rdbms' (inert otherwise). Running Camunda against 'mysql' requires a custom Camunda image carrying the MySQL JDBC driver, which the published image does not include: https://docs.camunda.io/docs/self-managed/deployment/manual/rdbms/configuration/#user-supplied-drivers-oracle-mysql"

  validation {
    condition     = contains(["postgresql", "mysql"], var.db_engine)
    error_message = "db_engine must be either 'postgresql' or 'mysql'."
  }
}

################################
# Variables                    #
################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster to prefix resources"
}

variable "aws_profile" {
  type        = string
  description = "AWS Profile to use (null = use default credential chain)"
  default     = null
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

################################################################
#                       Security Options                        #
################################################################

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks to allow access to LoadBalancers"
}

# The Aurora port is deliberately not in this map. It follows db_engine
# (5432 PostgreSQL / 3306 MySQL) through local.db_port and is opened by
# dedicated rules in security.tf; a static entry here would drive both the
# dynamic "ingress" and dynamic "egress" blocks and so open the PostgreSQL
# port on a MySQL deployment.
variable "ports" {
  type = map(number)
  default = {
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
  }
  description = "The ports to open for the security groups within the VPC. The Aurora port is deliberately absent: it follows db_engine (5432 PostgreSQL / 3306 MySQL) and is opened by dedicated rules in security.tf, so it cannot fall out of sync with the engine."
}

################################################################
#                     Database Options                          #
################################################################

variable "db_name" {
  type        = string
  description = "Database name used by Camunda components"
  default     = "camunda"

  # Interpolated into SQL identifiers by the seed task on both engines, where
  # the surrounding quoting is only correct for a well-formed identifier.
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.db_name)) && length(var.db_name) <= 63
    error_message = "db_name must be a valid identifier: start with a letter or underscore, contain only letters, digits and underscores, and be at most 63 characters."
  }
}

variable "db_admin_username" {
  type        = string
  description = "Admin username for the Aurora cluster"
  default     = "camunda_admin"
  sensitive   = true
}

variable "db_admin_password" {
  type        = string
  description = "Optional override for the Aurora admin password. If empty, a random password is generated."
  default     = ""
  sensitive   = true
}

variable "db_extra_wrapper_plugins" {
  type        = list(string)
  default     = []
  description = "Additional AWS Advanced JDBC Wrapper plugins to append to the generated JDBC URL. The module always sets 'failover' (and 'iam' when db_iam_auth_enabled), so list only the extras, e.g. ['readWriteSplitting']. Note that EFM/EFM2 also need 'initialConnection' on the Aurora Global writer endpoint this deployment connects to, so adding 'efm2' alone will not attach it. Only applies when secondary_storage_type = 'rdbms'."
}

variable "db_extra_url_parameters" {
  type        = map(string)
  default     = {}
  description = "Additional query parameters appended to the generated JDBC URL, e.g. { connectTimeout = \"5000\" }. Entries here override the reference architecture's own (failoverTimeoutMs = 60000). The Aurora module rejects the parameters it builds itself (wrapperPlugins, globalClusterInstanceHostPatterns, TLS mode) as well as keys or values containing '&' or '='. Only applies when secondary_storage_type = 'rdbms'."
}

variable "db_iam_auth_enabled" {
  type        = bool
  description = "Enable IAM database authentication on the Aurora cluster. Must stay true for RDBMS secondary storage: this reference architecture wires no database password for the Camunda tasks, so IAM is the only way they authenticate."
  default     = true

  # Turning this off produces a cluster the deployment cannot reach: the seed
  # task creates the Camunda user with the IAM auth plugin and no password, the
  # module correctly drops 'iam' from wrapperPlugins, and the ECS task
  # definition carries a username but no CAMUNDA_..._RDBMS_PASSWORD. Rejecting
  # it at plan time beats a connection refused at runtime.
  validation {
    condition     = var.secondary_storage_type != "rdbms" || var.db_iam_auth_enabled
    error_message = "db_iam_auth_enabled must be true when secondary_storage_type = 'rdbms': this reference architecture authenticates the Camunda tasks to Aurora with IAM only and provisions no database password."
  }
}

variable "db_seed_enabled" {
  type        = bool
  description = "Run a one-time ECS task to create/grant IAM DB users"
  default     = true
}

variable "db_seed_iam_usernames" {
  type        = list(string)
  description = "Database users to create and grant rds_iam + privileges for"
  default     = ["camunda"]

  # Same reasoning as db_name: each entry lands inside quoted SQL on both
  # engines, and the quoting only holds for well-formed identifiers.
  validation {
    condition = alltrue([
      for u in var.db_seed_iam_usernames :
      can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", u)) && length(u) <= 63
    ])
    error_message = "Each db_seed_iam_usernames entry must be a valid identifier: start with a letter or underscore, contain only letters, digits and underscores, and be at most 63 characters."
  }
}

variable "db_seed_run_id" {
  type        = string
  description = "Increment this value to force the DB seed task to re-run on the next apply (e.g. '1' → '2'). All SQL is idempotent so re-running is safe."
  default     = "1"
}

################################################################
#                      S3 Options                               #
################################################################

variable "s3_force_destroy" {
  type        = bool
  default     = true
  description = "Allow Terraform to destroy S3 backup buckets even if they contain objects. Defaults to true because this is a reference / demo architecture and `terraform destroy` should clean up without manual S3 cleanup. Set to false before running a real workload through it so Terraform refuses to drop backup data."
}

################################################################
#                     Registry Options                          #
################################################################

variable "registry_username" {
  type        = string
  description = "(Optional) The username for the container registry"
  default     = ""
}

variable "registry_password" {
  type        = string
  description = "(Optional) The password for the container registry"
  default     = ""
}

################################################################
#                         KMS Options                          #
################################################################

variable "secrets_kms_key_arn" {
  description = "Optional existing KMS key ARN for region 0. If empty, a CMK is created."
  type        = string
  default     = ""
}

variable "secrets_kms_key_arn_accepter" {
  description = "Optional existing KMS key ARN for region 1. If empty, a CMK is created."
  type        = string
  default     = ""
}

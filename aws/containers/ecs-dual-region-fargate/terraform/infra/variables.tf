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
  description = "Aurora RDBMS engine for secondary storage: 'postgresql' or 'mysql'. NOTE: MySQL requires a Camunda image that bundles the MySQL JDBC driver; the default image does not include it."

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

variable "ports" {
  type = map(number)
  default = {
    postgresql                            = 5432
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
  }
  description = "The ports to open for the security groups within the VPC"
}

################################################################
#                     Database Options                          #
################################################################

variable "db_name" {
  type        = string
  description = "Database name used by Camunda components"
  default     = "camunda"
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

variable "db_iam_auth_enabled" {
  type        = bool
  description = "Enable IAM database authentication on the Aurora cluster"
  default     = true
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

################################################################
#                        Global Options                        #
################################################################

variable "prefix" {
  type        = string
  description = "The prefix to use for names of resources"
  default     = "camunda"
}

variable "registry_username" {
  type        = string
  description = "(Optional) The username for the container registry (e.g., Docker Hub)"
  default     = ""
}

variable "registry_password" {
  type        = string
  description = "(Optional) The password for the container registry (e.g., Docker Hub)"
  default     = ""
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

################################################################
#                       Network Options                        #
################################################################

variable "cidr_blocks" {
  type        = string
  default     = "10.190.0.0/16"
  description = "The CIDR block to use for the VPC"
}

################################################################
#                      Security Options                        #
################################################################

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer"
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
#                     Database / IAM Options                    #
################################################################

variable "db_name" {
  type        = string
  description = "Database name used by Camunda components"
  default     = "camunda"
}

variable "db_admin_username" {
  type        = string
  description = "Admin username for the Aurora PostgreSQL cluster (demo default; use Secrets Manager in production)"
  default     = "camunda_admin"
  sensitive   = true
}

variable "db_admin_password" {
  type        = string
  description = "Optional override for the Aurora PostgreSQL admin password. If empty, a random password is generated and stored in Secrets Manager."
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
  description = "Run a one-time ECS task to create/grant IAM DB users (uses db_admin_username/password)"
  default     = true
}

variable "db_seed_iam_usernames" {
  type        = list(string)
  description = "Database users to create and grant rds_iam + privileges for (used for IAM DB auth)"
  default     = ["camunda"]
}

################################################################
#                         KMS Options                          #
################################################################

variable "secrets_kms_key_arn" {
  description = "Optional existing KMS key ARN to use for encrypting Secrets Manager secrets. If empty, this stack will create and manage a CMK."
  type        = string
  default     = ""
}

variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

################################################################
#                     Inputs from the network stage            #
################################################################

variable "vpc_id" {
  type        = string
  description = "Network stage output: ID of the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "Network stage output: CIDR block of the VPC, allowed to reach the database"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Network stage output: private subnet IDs (at least 3, distinct availability zones)"
}

variable "additional_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks of other VPCs, for example the second region, allowed to reach the database. Empty for a single region."
}

################################################################
#                     Inputs from the compute stage            #
################################################################

variable "ecs_cluster_arn" {
  type        = string
  description = "Compute stage output: ARN of the ECS cluster that runs the one-time database seed task"
}

variable "task_execution_role_arn" {
  type        = string
  description = "Compute stage output: ARN of the ECS task execution role"
}

variable "task_execution_role_name" {
  type        = string
  description = "Compute stage output: name of the ECS task execution role. The database admin secret read policy is attached to it."
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Compute stage output: KMS key that encrypts the secrets"
}

variable "seed_security_group_ids" {
  type        = list(string)
  description = "Compute stage outputs: security groups of the seed task (camunda_ports_security_group_id and egress_security_group_id)"
}

################################################################
#                          Database                            #
################################################################

variable "db_name" {
  type        = string
  default     = "camunda"
  description = "Name of the database Camunda uses"
}

variable "db_admin_username" {
  type        = string
  default     = "camunda_admin"
  description = "Admin user of the Aurora cluster"
}

variable "db_admin_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Admin password. When empty, a random one is generated and stored in Secrets Manager."
}

variable "db_iam_auth_enabled" {
  type        = bool
  default     = true
  description = "Enable IAM database authentication. Camunda connects through the AWS JDBC wrapper with the iam plugin."

  validation {
    condition     = var.db_iam_auth_enabled
    error_message = "db_iam_auth_enabled must be true: the Camunda stage connects with wrapperPlugins=iam."
  }
}

variable "db_instance_class" {
  type        = string
  default     = "db.t3.medium"
  description = "Instance class of the Aurora instance. Aurora Global Databases do not support db.t3/db.t4g: pick an r-class (for example db.r6g.large) or db.serverless if you plan to add a second region."
}

variable "db_num_instances" {
  type        = number
  default     = 1
  description = "Number of Aurora instances"
}

variable "global_cluster_identifier" {
  type        = string
  default     = null
  description = "Set once the cluster has been attached to an Aurora Global Database, so that Terraform does not plan to detach it. Leave null for a standalone cluster."
}

variable "db_seed_enabled" {
  type        = bool
  default     = true
  description = "Run a one-time ECS task that creates the IAM-authenticated database users. Needs the AWS CLI where Terraform runs."
}

variable "db_seed_iam_usernames" {
  type        = list(string)
  default     = ["camunda"]
  description = "Database users created for IAM authentication"
}

variable "databases" {
  type = map(object({
    database_name = string
    username      = string
    auth          = optional(string, "iam")
  }))
  default     = {}
  description = "Further databases on the cluster for components that need their own, such as the OIDC provider, Management Identity, and Camunda Hub. Each gets a role and a database. auth = iam: the role authenticates with an IAM token (no password). auth = password: a random password is generated and stored in Secrets Manager."

  validation {
    condition = alltrue([
      for k, d in var.databases :
      can(regex("^[a-z][a-z0-9_]{0,62}$", d.database_name)) && can(regex("^[a-z][a-z0-9_]{0,62}$", d.username))
    ])
    error_message = "database_name and username must be lowercase letters, digits, and underscores, starting with a letter: they are used in SQL statements."
  }

  validation {
    condition     = alltrue([for k, d in var.databases : contains(["iam", "password"], d.auth)])
    error_message = "auth must be iam or password."
  }

  validation {
    condition     = alltrue([for k, d in var.databases : d.auth == "password" || var.db_iam_auth_enabled])
    error_message = "auth = iam requires db_iam_auth_enabled = true."
  }
}

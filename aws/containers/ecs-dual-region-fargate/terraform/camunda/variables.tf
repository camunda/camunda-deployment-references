################################
# Magic Variables             #
################################

locals {
  owner = {
    region           = "eu-west-1" # London
    vpc_cidr_block   = "10.192.0.0/16"
    region_full_name = "dublin"
  }
  accepter = {
    region           = "eu-west-3" # Paris
    vpc_cidr_block   = "10.202.0.0/16"
    region_full_name = "paris"
  }
}

################################
# Variables                    #
################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster — must match the value used in the infra layer"
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
#                     Infra State Reference                     #
################################################################

variable "infra_state_path" {
  type        = string
  default     = "../infra/terraform.tfstate"
  description = <<-EOT
    Path to the infra layer's local Terraform state file.
    Default works when both layers use local state and the standard directory layout.
    For a remote backend (S3, Terraform Cloud, etc.) replace the
    data "terraform_remote_state" block in infra.tf with the appropriate backend type.
  EOT
}

################################################################
#                     Database Options                          #
################################################################

variable "db_name" {
  type        = string
  description = "Database name — must match the value used in the infra layer"
  default     = "camunda"
}

variable "db_seed_enabled" {
  type        = bool
  description = "Run a one-time ECS task to create/grant IAM DB users"
  default     = true
}

variable "db_seed_run_id" {
  type        = string
  description = "Increment this value to force the DB seed task to re-run on the next apply (e.g. '1' → '2'). All SQL is idempotent so re-running is safe."
  default     = "1"
}

variable "db_seed_iam_usernames" {
  type        = list(string)
  description = "Database users to create and grant rds_iam + privileges for"
  default     = ["camunda"]
}

variable "db_iam_auth_enabled" {
  type        = bool
  description = "Must match the value set in the infra layer (used by the DB seed task)"
  default     = true
}

variable "db_admin_username" {
  type        = string
  description = "Admin username — must match the value used in the infra layer"
  default     = "camunda_admin"
  sensitive   = true
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
#                         S3 Options                            #
################################################################

variable "s3_force_destroy" {
  type        = bool
  default     = false
  description = "Passed through to the orchestration cluster module — must match the infra layer value to avoid conflicts on destroy."
}

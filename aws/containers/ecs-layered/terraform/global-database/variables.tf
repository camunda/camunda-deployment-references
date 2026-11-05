variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

variable "region_a" {
  type        = string
  description = "Region of the existing Aurora cluster (the primary of the global database)"
}

variable "region_b" {
  type        = string
  description = "Region of the secondary cluster"
}

################################################################
#               Inputs from the storage layer (region A)       #
################################################################

variable "source_cluster_arn" {
  type        = string
  description = "Storage layer output cluster_arn: the existing cluster, which becomes the primary"
}

variable "source_cluster_identifier" {
  type        = string
  description = "Storage layer output cluster_identifier"
}

variable "source_cluster_endpoint" {
  type        = string
  description = "Storage layer output secondary_storage.host: writer endpoint of the existing cluster"
}

variable "source_cluster_resource_id" {
  type        = string
  description = "Storage layer output cluster_resource_id"
}

variable "database_name" {
  type        = string
  default     = "camunda"
  description = "Name of the database Camunda uses (same as the storage layer)"
}

variable "db_users" {
  type        = list(string)
  default     = ["camunda"]
  description = "IAM database users. A connect policy covering both clusters is created per user."
}

################################################################
#                Inputs from the network layers                #
################################################################

variable "vpc_id_a" {
  type        = string
  description = "Network layer output in region_a: VPC ID"
}

variable "vpc_cidr_a" {
  type        = string
  description = "Network layer output in region_a: VPC CIDR"
}

variable "vpc_id_b" {
  type        = string
  description = "Network layer output in region_b: VPC ID"
}

variable "vpc_cidr_b" {
  type        = string
  description = "Network layer output in region_b: VPC CIDR"
}

variable "private_subnet_ids_b" {
  type        = list(string)
  description = "Network layer output in region_b: private subnet IDs"
}

################################################################
#                       Secondary cluster                      #
################################################################

variable "engine_version" {
  type = string
  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  default     = "18.6"
  description = "Engine version. Must equal the version of the existing cluster."
}

variable "secondary_instance_class" {
  type        = string
  default     = "db.r6g.large"
  description = "Instance class of the secondary. Global databases do not support db.t3/db.t4g, and the primary must also be an r-class or serverless instance before the global cluster can be created."

  validation {
    condition     = !can(regex("^db\\.t[34]g?\\.", var.secondary_instance_class))
    error_message = "Aurora Global Databases do not support db.t3 and db.t4g instance classes."
  }
}

variable "secondary_num_instances" {
  type        = number
  default     = 1
  description = "Number of instances of the secondary cluster"
}

variable "iam_auth_enabled" {
  type        = bool
  default     = true
  description = "IAM database authentication on the secondary (same as the primary)"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Let Terraform detach the members when destroying the global cluster. Dev and test only. The provider requires the attribute whenever the global cluster is created from an existing cluster, hence false rather than null."
}

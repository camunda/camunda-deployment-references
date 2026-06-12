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

variable "region_0_cidr" {
  type        = string
  default     = "10.192.0.0/16"
  description = "VPC CIDR block for region 0"
}

variable "region_1_cidr" {
  type        = string
  default     = "10.202.0.0/16"
  description = "VPC CIDR block for region 1"
}

################################################################
#                    Networking Options                         #
################################################################

variable "networking_mode" {
  type        = string
  default     = "transit_gateway"
  description = "Cross-region networking: 'transit_gateway' or 'vpc_peering'"

  validation {
    condition     = contains(["transit_gateway", "vpc_peering"], var.networking_mode)
    error_message = "Must be 'transit_gateway' or 'vpc_peering'."
  }
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

################################################################
#                     Container Image                          #
################################################################

variable "camunda_image" {
  type        = string
  default     = "camunda/camunda:8.9.0"
  description = "Container image for Camunda orchestration and connectors tasks"
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

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "If true, only one NAT gateway will be created per region to save on e.g. IPs, not good for HA"
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
  description = "Admin username for the Aurora PostgreSQL cluster"
  default     = "camunda_admin"
  sensitive   = true
}

variable "db_admin_password" {
  type        = string
  description = "Optional override for the Aurora PostgreSQL admin password. If empty, a random password is generated."
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
#                      DNS Options                              #
################################################################

variable "enable_cross_region_dns_resolver" {
  type        = bool
  default     = false
  description = <<-EOT
    Create Route 53 Resolver endpoints and forwarding rules for cross-region Cloud Map DNS.
    Requires the IAM permission route53resolver:CreateResolverEndpoint on the calling principal.
    Zeebe Raft and Connectors work without this because cross-region contact uses NLB DNS names.
    Enable once the permission is granted if you need cross-region Service Connect name resolution.
  EOT
}

################################################################
#                      S3 Options                               #
################################################################

variable "s3_force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to destroy S3 backup buckets even if they contain objects"
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

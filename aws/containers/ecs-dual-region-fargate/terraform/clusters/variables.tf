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
  description = "Name of the cluster to prefix resources"
  default     = "yes"
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
  type    = list(string)
  default = ["0.0.0.0/0"]
  description = <<-EOT
    List of CIDR blocks to restrict access to the public-facing LoadBalancers
    (ports 80, 443, 26500, 9600).
    Security note: the default ["0.0.0.0/0"] allows unrestricted public access.
    Restrict to known IP ranges (e.g. office egress, VPN CIDRs) in production.
  EOT
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

variable "s3_force_destroy" {
  type        = bool
  default     = true
  description = "Allow terraform destroy to delete S3 backup buckets even when they contain objects. Set to true for dev/test environments where losing backups on destroy is acceptable."
}

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

variable "enable_cross_region_dns_resolver" {
  type    = bool
  default = false
  description = <<-EOT
    Create Route 53 Resolver endpoints and forwarding rules for cross-region Cloud Map DNS.
    Requires the IAM permission route53resolver:CreateResolverEndpoint on the calling principal.
    Zeebe Raft and Connectors work without this because cross-region contact uses NLB DNS names.
    Enable once the permission is granted if you need cross-region Service Connect name resolution.
  EOT
}

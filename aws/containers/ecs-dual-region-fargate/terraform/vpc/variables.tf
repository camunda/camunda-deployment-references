################################################################
#                       BYO-VPC Toggle                          #
################################################################

variable "byo_vpc" {
  type        = bool
  default     = false
  description = <<-EOT
    If true, this state consumes existing VPCs from the region_{0,1}_vpc_id
    variables (and friends) and only creates cross-region peering/TGW plus
    optional Route 53 Resolver endpoints. If false (default), Terraform
    creates two VPCs from scratch using terraform-aws-modules/vpc/aws.

    When true: region_{0,1}_vpc_id, region_{0,1}_vpc_cidr, and at least 3
    private + 3 database subnet IDs per region MUST be supplied. Validation
    is enforced by check blocks at plan time.
  EOT
}

################################################################
#                  Region & Naming Variables                    #
################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster to prefix resources (used for created resources only — BYO resources keep their existing names)"
}

variable "aws_profile" {
  type        = string
  description = "AWS Profile to use (null = use default credential chain)"
  default     = null
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all created resources"
}

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
#                  Greenfield VPC Inputs                        #
#  (used only when byo_vpc = false)                             #
################################################################

variable "region_0_cidr" {
  type        = string
  default     = "10.192.0.0/16"
  description = "VPC CIDR block to create for region 0 (only used when byo_vpc = false)"

  validation {
    condition     = can(cidrnetmask(var.region_0_cidr))
    error_message = "region_0_cidr must be a valid CIDR block."
  }
}

variable "region_1_cidr" {
  type        = string
  default     = "10.202.0.0/16"
  description = "VPC CIDR block to create for region 1 (only used when byo_vpc = false)"

  validation {
    condition     = can(cidrnetmask(var.region_1_cidr))
    error_message = "region_1_cidr must be a valid CIDR block."
  }
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "If true, only one NAT gateway will be created per region to save on e.g. IPs, not good for HA. Only used when byo_vpc = false."
}

################################################################
#                       BYO-VPC Inputs                          #
#  (used only when byo_vpc = true; validated by check blocks)   #
################################################################

variable "region_0_vpc_id" {
  type        = string
  default     = ""
  description = "Existing VPC ID in region 0 (required when byo_vpc = true)"

  validation {
    condition     = var.region_0_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.region_0_vpc_id))
    error_message = "region_0_vpc_id must match vpc-xxxxxxxx (8-17 hex chars) or be empty."
  }
}

variable "region_1_vpc_id" {
  type        = string
  default     = ""
  description = "Existing VPC ID in region 1 (required when byo_vpc = true)"

  validation {
    condition     = var.region_1_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.region_1_vpc_id))
    error_message = "region_1_vpc_id must match vpc-xxxxxxxx (8-17 hex chars) or be empty."
  }
}

variable "region_0_vpc_cidr" {
  type        = string
  default     = ""
  description = "CIDR block of the existing VPC in region 0 (required when byo_vpc = true)"

  validation {
    condition     = var.region_0_vpc_cidr == "" || can(cidrnetmask(var.region_0_vpc_cidr))
    error_message = "region_0_vpc_cidr must be a valid CIDR block or empty."
  }
}

variable "region_1_vpc_cidr" {
  type        = string
  default     = ""
  description = "CIDR block of the existing VPC in region 1 (required when byo_vpc = true)"

  validation {
    condition     = var.region_1_vpc_cidr == "" || can(cidrnetmask(var.region_1_vpc_cidr))
    error_message = "region_1_vpc_cidr must be a valid CIDR block or empty."
  }
}

variable "region_0_private_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Existing private subnet IDs in region 0 (≥3 across distinct AZs, required when byo_vpc = true)"

  validation {
    condition = length(var.region_0_private_subnet_ids) == 0 || alltrue([
      for s in var.region_0_private_subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))
    ])
    error_message = "Each region_0_private_subnet_ids entry must match subnet-xxxxxxxx."
  }
}

variable "region_1_private_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Existing private subnet IDs in region 1 (≥3 across distinct AZs, required when byo_vpc = true)"

  validation {
    condition = length(var.region_1_private_subnet_ids) == 0 || alltrue([
      for s in var.region_1_private_subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))
    ])
    error_message = "Each region_1_private_subnet_ids entry must match subnet-xxxxxxxx."
  }
}

variable "region_0_public_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Existing public subnet IDs in region 0 (≥3 across distinct AZs, used for ALBs; required when byo_vpc = true)"

  validation {
    condition = length(var.region_0_public_subnet_ids) == 0 || alltrue([
      for s in var.region_0_public_subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))
    ])
    error_message = "Each region_0_public_subnet_ids entry must match subnet-xxxxxxxx."
  }
}

variable "region_1_public_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Existing public subnet IDs in region 1 (≥3 across distinct AZs, used for ALBs; required when byo_vpc = true)"

  validation {
    condition = length(var.region_1_public_subnet_ids) == 0 || alltrue([
      for s in var.region_1_public_subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))
    ])
    error_message = "Each region_1_public_subnet_ids entry must match subnet-xxxxxxxx."
  }
}

variable "region_0_private_route_table_ids" {
  type        = list(string)
  default     = []
  description = "Route table IDs associated with region 0 private subnets. Peering/TGW routes are added to these. Required when byo_vpc = true."

  validation {
    condition = length(var.region_0_private_route_table_ids) == 0 || alltrue([
      for r in var.region_0_private_route_table_ids : can(regex("^rtb-[0-9a-f]{8,17}$", r))
    ])
    error_message = "Each region_0_private_route_table_ids entry must match rtb-xxxxxxxx."
  }
}

variable "region_1_private_route_table_ids" {
  type        = list(string)
  default     = []
  description = "Route table IDs associated with region 1 private subnets. Peering/TGW routes are added to these. Required when byo_vpc = true."

  validation {
    condition = length(var.region_1_private_route_table_ids) == 0 || alltrue([
      for r in var.region_1_private_route_table_ids : can(regex("^rtb-[0-9a-f]{8,17}$", r))
    ])
    error_message = "Each region_1_private_route_table_ids entry must match rtb-xxxxxxxx."
  }
}

################################################################
#                    Networking Options                         #
################################################################

variable "networking_mode" {
  type        = string
  default     = "vpc_peering"
  description = "Cross-region networking: 'vpc_peering' (default — simpler, no per-attachment hourly fee, fits two regions) or 'transit_gateway' (hub-and-spoke, needed when extending the topology beyond two VPCs)."

  validation {
    condition     = contains(["transit_gateway", "vpc_peering"], var.networking_mode)
    error_message = "Must be 'transit_gateway' or 'vpc_peering'."
  }
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

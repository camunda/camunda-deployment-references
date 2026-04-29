################################
# Magic Variables             #
################################

locals {
  # For demonstration purposes, we will use owner and acceptor as separation. Naming choice will become clearer when seeing the peering setup
  owner = {
    region             = "eu-west-2"     # London
    vpc_cidr_block     = "10.192.0.0/16" # vpc for the cluster and pod range
    service_cidr_block = "10.190.0.0/16" # internal network of the cluster
    region_full_name   = "london"
  }
  accepter = {
    region             = "eu-west-3"     # Paris
    vpc_cidr_block     = "10.202.0.0/16" # vpc for the cluster and pod range
    service_cidr_block = "10.200.0.0/16" # internal network of the cluster
    region_full_name   = "paris"
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

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use"
  # renovate: datasource=endoflife-date depName=amazon-eks versioning=loose
  default = "1.35"
}

variable "np_instance_types" {
  type        = list(string)
  description = "Instance types for the node pool"
  default     = ["m6i.xlarge"]
}

variable "np_capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Allows setting the capacity type to ON_DEMAND or SPOT to determine stable nodes"
}

variable "np_max_node_count" {
  type        = number
  default     = 10
  description = "Maximum number of nodes in the node pool"
}

variable "np_desired_node_count" {
  type        = number
  default     = 4
  description = "Desired number of nodes in the node pool"
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "If true, only one NAT gateway will be created to save on e.g. IPs, not good for HA"
}
variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

################################
# Connectivity                 #
################################

variable "connectivity_type" {
  type        = string
  description = "Type of connectivity between the two VPCs. 'peering' uses VPC Peering, 'transit-gateway' uses an existing AWS Transit Gateway."
  default     = "peering"
  validation {
    condition     = contains(["peering", "transit-gateway"], var.connectivity_type)
    error_message = "connectivity_type must be 'peering' or 'transit-gateway'."
  }
}

variable "transit_gateway_id" {
  type        = string
  description = "ID of an existing Transit Gateway to attach VPCs to. Required when connectivity_type is 'transit-gateway'."
  default     = null
}

variable "transit_gateway_ram_share_arn" {
  type        = string
  description = "ARN of a RAM share for the Transit Gateway. Required when the TGW is in a different AWS account."
  default     = null
}
